# AIOps Platform - Next Steps Implementation Plan

## Current Status: 60% MVP Complete

**Last Update**: 2026-02-28  
**Code**: ~2,100 LOC Python + Terraform modules  
**Test Coverage**: ~30% (ingestion+detection only; agents untested)

---

## 🔴 CRITICAL GAPS (Must Fix Before Production)

### 1. **Zero Test Coverage for Orchestration Agents** ⭐ HIGHEST PRIORITY
- All 5 agents (detection, correlation, historical, RCA, recommendation) have **NO unit tests**
- Files: `/src/orchestration/lambda/orchestrator/*.py` (336 LOC untested)
- Impact: Silent failures in production; operator blindness to RCA quality
- **What to Do**: Create `/tests/unit/test_orchestration_agents.py` with 50+ test cases mocking Bedrock
- **Effort**: 8-10 hours
- **Unblocks**: Tasks 2-10

### 2. **No CI/CD Pipeline** ⭐ CRITICAL
- No `.github/workflows/`; no automated test execution on PRs
- Impact: Breaking changes merge silently; code quality degradation
- **What to Do**: 
  - Create `.github/workflows/test.yml` → `pytest tests/unit/`
  - Create `tests/requirements.txt` with pytest, boto3-stubs, numpy, scipy
  - Create `.github/workflows/lint.yml` → ruff check, black format
- **Effort**: 6-8 hours
- **Do First**: Establishes test infrastructure baseline

### 3. **No Integration Tests** ⭐ HIGH
- `/tests/integration/` directory empty; pipeline never validated end-to-end
- Impact: Cross-component bugs only found in production
- **What to Do**: Create `/tests/integration/test_full_pipeline.py` with moto local DynamoDB
  - Test: anomaly write → orchestrator Lambda → all agents → Slack notification
  - Use moto to mock DynamoDB/S3 for isolated testing
- **Effort**: 8-10 hours
- **Depends**: Task 1 (CI/CD in place)

### 4. **Detection Policies Not Enforced** ⭐ HIGH
- DynamoDB policy store exists but NOT applied to detection
- Thresholds hardcoded in Lambda; sensitivity flags ignored
- Files: `/src/detection/statistical/main.py`, `/src/detection/rules/handler.py`
- Impact: Feature "configurable sensitivity per service" unreachable
- **What to Do**: 
  - Load policies from DynamoDB in `run_detection()`
  - Apply policy.sensitivity → σ threshold (low=4σ, medium=3σ, high=2σ)
  - Write tests: different policies → different detection counts
- **Effort**: 6-8 hours
- **Depends**: Task 1 (CI/CD + tests in place)

### 5. **Historical Compare Agent Incomplete** ⭐ MEDIUM-HIGH
- File: `/src/orchestration/lambda/orchestrator/historical_agent.py` (70 LOC)
- Only returns stub data; no actual DynamoDB queries
- Should return: similar past incidents, recurring frequency, deployment correlation
- Impact: RCA lacks "this happened before" context
- **What to Do**: 
  - Implement DynamoDB queries for similar incidents (7-day window)
  - Implement deployment lookup (±2 hours from anomaly)
  - Add tests
- **Effort**: 6-8 hours
- **Depends**: Tasks 1-2 (test infrastructure)

### 6. **No Bedrock Fallback & Cost Tracking** ⭐ MEDIUM-HIGH
- Bedrock unavailability → silent failures; no cost visibility
- Files: `/src/shared/bedrock_client.py`, all agent files
- Impact: Production cost surprises; resilience gaps
- **What to Do**: 
  - Add try/except around Bedrock calls in all agents
  - Return degraded responses (confidence="low", "Bedrock unavailable")
  - Add CloudWatch metrics: TokenCost, InputTokens, OutputTokens per agent
  - Create per-agent daily cost alarms
- **Effort**: 6 hours
- **Depends**: Tasks 1-2

---

## 🟠 HIGH PRIORITY (Complete MVP)

### 7. **End-to-End Test Suite** 
- File: `/tests/e2e/test_end_to_end.py` (create)
- Inject synthetic anomaly → verify Slack notification
- Enable local validation without AWS deployment
- **Effort**: 4-6 hours
- **Depends**: Tasks 1-6

### 8. **Add Production Observability**
- File: Create `/src/shared/metrics.py` (CloudWatch metrics)
- Track: Agent execution time, anomaly count, Bedrock API calls
- Modify: All agents to emit metrics
- **Effort**: 6-8 hours
- **Depends**: All core agents working

### 9. **Cross-Account Correlation**
- Current: CorrelationAgent only scans same-service anomalies
- Improve: Detect impact propagation across accounts/services
- **Effort**: 6-8 hours
- **Nice-to-Have** for MVP but needed for production

---

## 📊 TEST COVERAGE TARGETS

| Component | Current | After Tasks 1-7 | Target |
|-----------|---------|-----------------|--------|
| Ingestion | 85% | 90% | 90%+ |
| Detection | 80% | 85% | 85%+ |
| Agents | 0% | 70% | 80%+ |
| Alerting | 0% | 60% | 70%+ |
| Shared | 20% | 60% | 70%+ |
| **Overall** | **30%** | **60%** | **70%+** |

---

## ⚡ RECOMMENDED EXECUTION (14 Days)

### Week 1
- **Days 1-2**: Tasks 1 (CI/CD setup) + Task 3 (test requirements)
- **Days 3-4**: Task 2 (agent tests - 50+ cases)
- **Days 5-7**: Tasks 4 (historical agent) + Task 5 (Bedrock fallback)

### Week 2
- **Days 1-3**: Task 6 (integration tests with moto)
- **Days 4-5**: Task 7 (policy enforcement)
- **Days 6-7**: Task 8 (observability) + Task 9 (E2E test)

---

## 📋 FILES TO CREATE/MODIFY

### Must Create (NEW)
```
.github/workflows/test.yml
.github/workflows/lint.yml
tests/requirements.txt
tests/unit/test_orchestration_agents.py (300 LOC)
tests/integration/test_full_pipeline.py (200 LOC)
tests/integration/conftest.py
tests/e2e/test_end_to_end.py (100 LOC)
src/shared/metrics.py (100 LOC)
scripts/inject_test_event.py (50 LOC)
```

### Must Modify
```
src/orchestration/lambda/orchestrator/historical_agent.py (add DynamoDB queries)
src/orchestration/lambda/orchestrator/detection_agent.py (add exception handling)
src/orchestration/lambda/orchestrator/correlation_agent.py (add exception handling)
src/orchestration/lambda/orchestrator/rca_agent.py (add fallback handling)
src/orchestration/lambda/orchestrator/recommendation_agent.py (add fallback handling)
src/orchestration/lambda/orchestrator/handler.py (add metrics)
src/detection/statistical/main.py (wire policies)
src/detection/rules/handler.py (wire policies)
src/shared/bedrock_client.py (add cost tracking)
```

---

## 🎯 QUICK START: Run Unit Tests Now

```bash
# Install test deps
pip install -r requirements-dev.txt  # Create this file first

# Run existing tests
pytest tests/unit/ -v

# Current coverage: ~30%
pytest tests/unit/ --cov=src --cov-report=html
```

Expected: 4/5 test files pass; agents have NO tests (0% coverage).

---

## 🚀 Success Criteria (MVP Release Ready)

- ✅ Test coverage: 60%+ overall
- ✅ All agents tested (detection, correlation, historical, RCA, recommendation)
- ✅ CI/CD pipeline blocking broken PRs
- ✅ Integration tests validating full workflow
- ✅ Policy store enforcement working
- ✅ Production observability (CloudWatch metrics)
- ✅ E2E test with synthetic anomaly
- ✅ Bedrock fallback + cost tracking

**Estimated Timeline**: 2 engineers × 2.5 weeks = 60-70 engineer-hours

