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

The run generates collections (main, Smoke, Contract), `dev`/`prod` environments,
a private mock and a smoke monitor in the target workspace, and commits the
exported artifacts to `.postman/` and `postman/`. `.github/workflows/ci.yml` is
maintained in the repo: it reads the Smoke/Contract collection IDs from
`.postman/resources.yaml`, looks up the workspace's mock URL at run time and runs
both collections against it.

### Repeating the demo with a new workspace

1. Delete the old workspace and re-import the service from APIM.
2. Run the workflow and enter the new workspace ID (or change the `workspace-id`
   default in `postman-onboarding.yml`). If the new workspace is in a different
   sub-team, set `workspace-team-id` too.

When the workspace ID changes, the workflow clears the previously generated
`.postman/` and `postman/` files first, so nothing stale from the old workspace is reused.

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
