"""ClickHouse HTTP client using clickhouse-connect.

Configuration (env vars):
    CLICKHOUSE_HOST     - hostname or IP (required)
    CLICKHOUSE_PORT     - HTTP port (default: 8123)
    CLICKHOUSE_DATABASE - database name (default: aiops)
    CLICKHOUSE_USER     - username (default: default)
    CLICKHOUSE_PASSWORD - password (default: empty)
"""
import os
from typing import Any

import clickhouse_connect

from src.shared.logger import get_logger

logger = get_logger("clickhouse_client")


class ClickHouseClient:
    """Thin wrapper around clickhouse-connect for the AIOps Agentic System."""

    def __init__(
        self,
        host: str | None = None,
        port: int | None = None,
        database: str | None = None,
        user: str | None = None,
        password: str | None = None,
    ) -> None:
        self._host = host or os.environ["CLICKHOUSE_HOST"]
        self._port = int(port or os.environ.get("CLICKHOUSE_PORT", 8123))
        self._database = database or os.environ.get("CLICKHOUSE_DATABASE", "aiops")
        self._user = user or os.environ.get("CLICKHOUSE_USER", "default")
        self._password = password or os.environ.get("CLICKHOUSE_PASSWORD", "")

        self._client = clickhouse_connect.get_client(
            host=self._host,
            port=self._port,
            database=self._database,
            username=self._user,
            password=self._password,
            connect_timeout=10,
            send_receive_timeout=30,
        )

    def insert(self, table: str, data: list[dict[str, Any]]) -> None:
        """Insert a list of row dicts into a ClickHouse table.

        Args:
            table: Target table name (unqualified; uses the configured database).
            data:  List of dicts where each dict maps column name to value.
        """
        if not data:
            return
        columns = list(data[0].keys())
        rows = [[row.get(c) for c in columns] for row in data]
        self._client.insert(table, rows, column_names=columns)
        logger.debug("Inserted rows", extra={"table": table, "count": len(data)})

    def query(self, sql: str) -> list[dict[str, Any]]:
        """Execute a SELECT query and return rows as a list of dicts.

        Args:
            sql: Raw SQL string.

        Returns:
            List of row dicts keyed by column name.
        """
        result = self._client.query(sql)
        return [dict(zip(result.column_names, row)) for row in result.result_rows]

    def query_scalar(self, sql: str) -> Any:
        """Execute a query that returns a single scalar value.

        Returns None if the result set is empty.
        """
        rows = self.query(sql)
        if not rows:
            return None
        return next(iter(rows[0].values()))
