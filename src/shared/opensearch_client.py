"""OpenSearch client with SigV4 authentication.

Supports both OpenSearch Serverless (service name ``aoss``) and managed
OpenSearch Service domains (service name ``es``). The service is selected via
the ``OPENSEARCH_SERVICE`` environment variable (default: ``es``).
"""
import os
from typing import Any

import boto3
from opensearchpy import OpenSearch, RequestsHttpConnection, AWSV4SignerAuth

from src.shared.logger import get_logger

logger = get_logger("opensearch_client")


class OpenSearchClient:
    """Wrapper around opensearch-py with AWS SigV4 auth for OpenSearch Serverless."""

    def __init__(self, endpoint: str | None = None, region: str | None = None, service: str | None = None) -> None:
        self._endpoint = (endpoint or os.environ["OPENSEARCH_ENDPOINT"]).rstrip("/")
        self._region = region or os.environ.get("AWS_REGION", "eu-central-1")
        self._service = (service or os.environ.get("OPENSEARCH_SERVICE", "es")).lower()

        # Strip https:// for the host parameter
        host = self._endpoint.replace("https://", "").replace("http://", "")

        credentials = boto3.Session().get_credentials()
        auth = AWSV4SignerAuth(credentials, self._region, self._service)

        self._client = OpenSearch(
            hosts=[{"host": host, "port": 443}],
            http_auth=auth,
            use_ssl=True,
            verify_certs=True,
            connection_class=RequestsHttpConnection,
            pool_maxsize=10,
        )

    def index(self, index: str, doc: dict[str, Any], doc_id: str | None = None) -> dict[str, Any]:
        """Index a single document.

        Args:
            index: Index name.
            doc: Document body.
            doc_id: Optional document ID; auto-generated if omitted.

        Returns:
            OpenSearch response dict.
        """
        kwargs: dict[str, Any] = {"index": index, "body": doc}
        if doc_id:
            kwargs["id"] = doc_id
        response = self._client.index(**kwargs)
        logger.debug("Indexed document", extra={"index": index, "result": response.get("result")})
        return response

    def search(self, index: str, body: dict[str, Any]) -> dict[str, Any]:
        """Execute a search query.

        Args:
            index: Index name or pattern (e.g. ``logs-*``).
            body: OpenSearch query DSL.

        Returns:
            OpenSearch response dict.
        """
        response = self._client.search(index=index, body=body)
        hits = response.get("hits", {}).get("total", {}).get("value", 0)
        logger.debug("Search executed", extra={"index": index, "hits": hits})
        return response

    def bulk_index(self, index: str, docs: list[dict[str, Any]]) -> dict[str, Any]:
        """Bulk-index multiple documents.

        Args:
            index: Target index name.
            docs: List of document bodies. Each doc gets an auto-generated ID.

        Returns:
            OpenSearch bulk response dict.
        """
        if not docs:
            return {"errors": False, "items": []}

        bulk_body: list[dict[str, Any]] = []
        for doc in docs:
            bulk_body.append({"index": {"_index": index}})
            bulk_body.append(doc)

        response = self._client.bulk(body=bulk_body)
        error_count = sum(
            1 for item in response.get("items", [])
            if item.get("index", {}).get("error")
        )
        if error_count:
            logger.warning(
                "Bulk index had errors",
                extra={"index": index, "total": len(docs), "errors": error_count},
            )
        else:
            logger.debug("Bulk indexed", extra={"index": index, "count": len(docs)})
        return response
