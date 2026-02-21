SHELL := /bin/bash
.DEFAULT_GOAL := help

# ── Configuration (override via env or CLI: make deploy ENV=staging) ──────────
ENV                ?= dev
AWS_REGION         ?= eu-central-1
PROJECT_PREFIX     ?= aiops
FARGATE_PLATFORM   ?= linux/amd64

# ── Source paths ──────────────────────────────────────────────────────────────
SRC_SHARED         := src/shared
LOG_NORMALIZER_SRC := src/ingestion/lambda/log-normalizer
RULE_DETECTION_SRC := src/detection/rules
ORCHESTRATOR_SRC   := src/orchestration/lambda/orchestrator
FARGATE_DOCKERFILE := src/detection/statistical/Dockerfile

# ── Build staging dirs (gitignored via **/.builds/) ───────────────────────────
LOG_NORMALIZER_BUILD := terraform/modules/ingestion/.builds/log-normalizer-pkg
RULE_DETECTION_BUILD := terraform/modules/compute/.builds/rule-detection-pkg
ORCHESTRATOR_BUILD   := terraform/modules/compute/.builds/orchestrator-pkg

TF_DIR := terraform/environments/$(ENV)

# ── Derived (lazy — evaluated only when used) ─────────────────────────────────
# Use project venv if present, otherwise fall back to system python3
PYTHON          = $(or $(wildcard venv/bin/python3), python3)
AWS_ACCOUNT_ID  = $(shell aws sts get-caller-identity --query Account --output text 2>/dev/null)
ECR_REGISTRY    = $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com
ECR_REPO        = $(ECR_REGISTRY)/$(PROJECT_PREFIX)-$(ENV)-statistical-detection

# ─────────────────────────────────────────────────────────────────────────────

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?##' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-32s\033[0m %s\n", $$1, $$2}' | sort

# ── Build ─────────────────────────────────────────────────────────────────────

.PHONY: build
build: build-lambdas build-fargate ## Build everything: all Lambda packages + Fargate image

.PHONY: build-lambdas
build-lambdas: build-log-normalizer build-rule-detection build-orchestrator ## Stage all Lambda packages (source + shared + pip deps)

.PHONY: build-log-normalizer
build-log-normalizer: ## Stage log-normalizer Lambda
	@echo "→ Building log-normalizer..."
	rm -rf $(LOG_NORMALIZER_BUILD)
	mkdir -p $(LOG_NORMALIZER_BUILD)/shared
	pip install -q --upgrade -r $(LOG_NORMALIZER_SRC)/requirements.txt -t $(LOG_NORMALIZER_BUILD)
	cp $(LOG_NORMALIZER_SRC)/handler.py $(LOG_NORMALIZER_BUILD)/
	cp $(SRC_SHARED)/logger.py $(SRC_SHARED)/opensearch_client.py $(LOG_NORMALIZER_BUILD)/shared/
	touch $(LOG_NORMALIZER_BUILD)/shared/__init__.py
	@echo "  ✓ log-normalizer staged at $(LOG_NORMALIZER_BUILD)"

.PHONY: build-rule-detection
build-rule-detection: ## Stage rule-detection Lambda
	@echo "→ Building rule-detection..."
	rm -rf $(RULE_DETECTION_BUILD)
	mkdir -p $(RULE_DETECTION_BUILD)/shared
	pip install -q --upgrade -r $(RULE_DETECTION_SRC)/requirements.txt -t $(RULE_DETECTION_BUILD)
	cp $(RULE_DETECTION_SRC)/handler.py $(RULE_DETECTION_BUILD)/
	cp $(SRC_SHARED)/logger.py $(SRC_SHARED)/opensearch_client.py $(RULE_DETECTION_BUILD)/shared/
	touch $(RULE_DETECTION_BUILD)/shared/__init__.py
	@echo "  ✓ rule-detection staged at $(RULE_DETECTION_BUILD)"

.PHONY: build-orchestrator
build-orchestrator: ## Stage orchestrator Lambda (all agents + shared + bedrock client)
	@echo "→ Building orchestrator..."
	rm -rf $(ORCHESTRATOR_BUILD)
	mkdir -p $(ORCHESTRATOR_BUILD)/shared
	pip install -q --upgrade -r $(ORCHESTRATOR_SRC)/requirements.txt -t $(ORCHESTRATOR_BUILD)
	cp $(ORCHESTRATOR_SRC)/*.py $(ORCHESTRATOR_BUILD)/
	cp $(SRC_SHARED)/logger.py $(SRC_SHARED)/opensearch_client.py $(SRC_SHARED)/bedrock_client.py \
	  $(ORCHESTRATOR_BUILD)/shared/
	touch $(ORCHESTRATOR_BUILD)/shared/__init__.py
	@echo "  ✓ orchestrator staged at $(ORCHESTRATOR_BUILD)"

# ── Fargate image ─────────────────────────────────────────────────────────────

.PHONY: build-fargate
build-fargate: ## Build and push Fargate detection image to ECR (run after tf-apply creates the ECR repo)
	@test -n "$(AWS_ACCOUNT_ID)" || (echo "ERROR: AWS credentials not configured" && exit 1)
	@docker info > /dev/null 2>&1 || (echo "ERROR: Docker daemon unreachable — run 'docker context ls' and switch with 'docker context use <name>'" && exit 1)
	@echo "→ Authenticating with ECR ($(ECR_REGISTRY))..."
	aws ecr get-login-password --region $(AWS_REGION) | \
	  docker login --username AWS --password-stdin $(ECR_REGISTRY)
	@echo "→ Building $(FARGATE_PLATFORM) image and pushing to $(ECR_REPO):latest ..."
	docker buildx build \
	  --platform $(FARGATE_PLATFORM) \
	  -t $(ECR_REPO):latest \
	  -f $(FARGATE_DOCKERFILE) \
	  --push \
	  src/
	@echo "  ✓ Fargate image pushed ($(FARGATE_PLATFORM))"

# ── Terraform ─────────────────────────────────────────────────────────────────

.PHONY: tf-init
tf-init: ## terraform init for ENV (default: dev)
	terraform -chdir=$(TF_DIR) init -reconfigure -backend-config=backend.conf

.PHONY: tf-plan
tf-plan: build-lambdas ## Stage Lambda packages then terraform plan
	terraform -chdir=$(TF_DIR) plan -var-file=$(ENV).tfvars

.PHONY: tf-apply
tf-apply: build-lambdas ## Stage Lambda packages then terraform apply
	terraform -chdir=$(TF_DIR) apply -var-file=$(ENV).tfvars -auto-approve

.PHONY: tf-destroy
tf-destroy: ## terraform destroy for ENV (prompts for confirmation)
	terraform -chdir=$(TF_DIR) destroy -var-file=$(ENV).tfvars

# ── Full deploy ───────────────────────────────────────────────────────────────

.PHONY: deploy
deploy: build-lambdas tf-apply build-fargate ## Full deploy: stage Lambdas → terraform apply → push Fargate image
	@echo "✓ Deploy complete (ENV=$(ENV))"

# ── Operations ───────────────────────────────────────────────────────────────

.PHONY: load-policies
load-policies: ## Load detection policies into DynamoDB (ENV=dev, FILE=policies/examples/default-policies.yaml)
	scripts/load-policies.sh --file policies/examples/default-policies.yaml --env $(ENV) --region $(AWS_REGION)

.PHONY: inject-test-event
inject-test-event: ## Write a synthetic anomaly to DynamoDB to trigger the orchestrator pipeline
	$(PYTHON) scripts/inject_test_event.py --env $(ENV) --region $(AWS_REGION)

# ── Tests ─────────────────────────────────────────────────────────────────────

.PHONY: test
test: ## Run unit tests
	pytest tests/unit/ -v

.PHONY: test-integration
test-integration: ## Run integration tests (requires AWS credentials)
	pytest tests/integration/ -v

.PHONY: test-e2e
test-e2e: ## Run end-to-end tests
	pytest tests/e2e/ -v

# ── Clean ─────────────────────────────────────────────────────────────────────

.PHONY: clean
clean: ## Remove all Lambda staging directories and Terraform build artifacts
	rm -rf terraform/modules/ingestion/.builds
	rm -rf terraform/modules/compute/.builds
	@echo "✓ Build artifacts removed"
