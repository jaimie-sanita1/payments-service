# Payments API

Demo payments service used to show Postman API onboarding end to end.

* `src/index.js` — Express implementation of `openapi.yaml` (in-memory)
* `openapi.yaml` — OpenAPI 3.0 spec, source of truth for the Postman collections
* `.github/workflows/postman-onboarding.yml` — manual workflow that onboards the API to Postman
* `k8s/`, `scripts/` — kind cluster demo with the Postman Insights agent

## API

| Method | Path | Notes |
|---|---|---|
| POST | `/v1/payments` | Requires `Idempotency-Key`; replaying a key returns the original payment |
| GET | `/v1/payments/{paymentId}` | `404` for unknown ids |
| POST | `/v1/payments/{paymentId}/cancel` | Idempotent; `409` for `SETTLED`/`FAILED` payments |
| GET | `/health` | Liveness/readiness |

Seeded payments: `pay_1001` (`PENDING`) and `pay_1002` (`SETTLED`).

```bash
npm install
npm start            # http://localhost:3002
```

## Onboard to Postman

Actions → **Postman API onboarding** → Run workflow.

Required repo secrets:

* `POSTMAN_API_KEY` — service-account PMAK
* `GH_PAT` — fine-grained token with Contents + Workflows write on this repo

Optional, enables Postman Insights linking (human user, not the service account):

* `INSIGHTS_POSTMAN_API_KEY`
* `INSIGHTS_POSTMAN_ACCESS_TOKEN`

The run reuses the existing Payments API workspace and generates collections
(main, Smoke, Contract), environments, a private mock, a smoke monitor and a CI
workflow (`.github/workflows/ci.yml`). The generated CI runs the Smoke and
Contract collections against the `prod` environment, which points at the mock.

## Insights demo (kind)

Prerequisites: Docker, kind, kubectl, curl, and an Insights project for the service
in Postman (copy its `svc_...` Project ID).

```bash
export POSTMAN_API_KEY="PMAK_xxxxx"        # human-user key
export PAYMENTS_PROJECT_ID="svc_xxxxx"
export PAYMENTS_WORKSPACE_ID="a1ae5022-d368-4e0d-a65b-463f2099a9f5"   # default
export POSTMAN_SYSTEM_ENV="<system-env-uuid>"                          # optional

./scripts/run-demo.sh                       # cluster, ingress, Insights agent, payments-api
./scripts/simulate-traffic.sh --verbose --slow
```

Wait ~5-10 minutes for Insights to infer endpoints, then run the onboarding
workflow so it can link the discovered service to the workspace.

Teardown:

```bash
./scripts/teardown-demo.sh --dry-run
DELETE_CLUSTER=1 ./scripts/teardown-demo.sh
```
