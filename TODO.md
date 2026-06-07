# TODO — Fuse Control Plane (Elixir)

A Phoenix app that drives the **fuse** orchestrator (`dev/misc/fuse`) over its REST
API: provision/drain/destroy microVM environments, manage snapshots, watch hosts,
and surface everything in a live dashboard. Fuse owns the truth; this app is a
typed client, an optional local mirror, and a UI.

Fuse wire contract (Bearer auth, error envelope `{"error":{code,message,details}}`):

- Environments: `GET/POST /v1/environments`, `GET /v1/environments/{id}`,
  `GET /v1/environments/{id}/events` (SSE), `POST /v1/environments/{id}?action=rotate-token|drain`,
  `DELETE /v1/environments/{id}`
- Snapshots: `POST /v1/environments/{id}/snapshots`, `GET /v1/snapshots`,
  `GET /v1/snapshots/{id}`, `POST /v1/snapshots/{id}?action=restore`, `DELETE /v1/snapshots/{id}`
- Hosts: `POST/GET /v1/hosts`, `GET /v1/hosts/{id}`,
  `POST /v1/hosts/{id}?action=cordon|uncordon`, `DELETE /v1/hosts/{id}`

## Done (carried over)

- [x] Create Phoenix app at repo root (OTP app `:fuse`, namespace `Fuse` / `FuseWeb`)
- [ ] ~~Redis/Docker schema + context~~ (superseded — keep migration history, repurpose later)

## Phase 0 — Pure helpers (no HTTP, no DB)

- [x] `Fuse.Error` — parse the `{error:{code,message,details}}` envelope into a struct
- [x] `Fuse.ResourceSpec` — build/validate `{cpus, ram_mb, storage_gb, region, max_runtime_seconds}`
- [x] `Fuse.Plan` — size presets (`tiny`/`small`/`medium`/`large`) → `ResourceSpec`
- [x] `Fuse.State` — environment state enum + predicates (`running?`, `terminal?`, transitions)
- [x] `Fuse.SnapshotState` — snapshot state enum + predicates
- [x] `Fuse.Manifest` — encode/decode `manifest_inline` (base64 JSON) helper
- [x] Unit tests for each helper

## Phase 1 — HTTP client boundary

- [x] `Fuse.Client` — behaviour defining every fuse call
- [x] `Fuse.Client.HTTP` — `Req`-based impl (base URL + Bearer token from config)
- [x] Request-ID propagation (`X-Request-ID`) + structured logging
- [x] Map non-2xx → `{:error, %Fuse.Error{}}`; map transport errors
- [x] `Fuse.Client.Fake` — in-memory `Agent` impl for tests
- [x] Configurable impl swap (`config :fuse, :fuse_client, ...`)
- [x] Client unit tests against the fake

## Phase 2 — Environments context

- [ ] `Fuse.Environments.list/1` (filters: task_id, state, host_id)
- [ ] `Fuse.Environments.get/1`
- [ ] `Fuse.Environments.create/1` (task_id, spec, secrets, startup_script, gateway_*)
- [ ] `Fuse.Environments.drain/1`
- [ ] `Fuse.Environments.rotate_token/1`
- [ ] `Fuse.Environments.destroy/1`
- [ ] Decode wire JSON → `Fuse.Environments.Environment` struct
- [ ] Context tests against the fake client

## Phase 3 — Snapshots context

- [ ] `Fuse.Snapshots.create/2` (vm_id + comment/mode/retention/metadata/export_ref)
- [ ] `Fuse.Snapshots.list/1` (filters: vm_id, task_id, tenant_id, state)
- [ ] `Fuse.Snapshots.get/1`
- [ ] `Fuse.Snapshots.restore/1`
- [ ] `Fuse.Snapshots.delete/1`
- [ ] Decode → `Fuse.Snapshots.Snapshot` struct (incl. `exports`)
- [ ] Context tests

## Phase 4 — Hosts context

- [ ] `Fuse.Hosts.register/1`, `list/0`, `get/1`, `cordon/1`, `uncordon/1`, `remove/1`
- [ ] Decode → `Fuse.Hosts.Host` struct (capacity vs allocated)
- [ ] Context tests

## Phase 5 — Event streaming (SSE → PubSub)

- [ ] `Fuse.EventStream` — consume `GET /v1/environments/{id}/events`
- [ ] Supervised consumer per watched environment (or global stream)
- [ ] Parse SSE frames → typed events
- [ ] Broadcast to `Phoenix.PubSub` topics (`environments`, `environment:{id}`)
- [ ] Reconnect/backoff handling
- [ ] Fake event source for tests

## Phase 6 — Local mirror (optional, for cache/audit)

- [ ] Decide: thin proxy vs. Ecto-mirrored read model
- [ ] Repurpose existing migration or add `environments` / `snapshots` cache tables
- [ ] Upsert from list/get responses and from PubSub events
- [ ] Audit log of actions (who/what/when)

## Phase 7 — REST passthrough API

- [ ] `/api` router scope
- [ ] `EnvironmentController` (index/show/create/delete + drain/rotate-token actions)
- [ ] `SnapshotController` (index/show/create/delete + restore)
- [ ] `HostController` (index/show/register/delete + cordon/uncordon)
- [ ] JSON error rendering mirroring fuse's envelope
- [ ] Controller tests

## Phase 8 — LiveView dashboard

- [ ] Environments list + state badges + host column
- [ ] Environment detail (spec, URL, live event log via PubSub)
- [ ] Create-environment form (plan presets)
- [ ] Drain / destroy / rotate-token actions
- [ ] Snapshots panel (create / restore / delete)
- [ ] Hosts panel (capacity vs allocated, cordon/uncordon)
- [ ] Loading + error states; DOM IDs for tests
- [ ] LiveView tests

## Phase 9 — Auth & safety

- [ ] Fuse Bearer token from runtime config / secrets (never logged)
- [ ] App-side auth for `/api` writes and dashboard
- [ ] Validate resource bounds before forwarding to fuse
- [ ] Confirm-before-destroy on drain/destroy/restore
- [ ] Rate limit write endpoints

## Phase 10 — Integration & hardening

- [ ] `FUSE_INTEGRATION=1` gate hitting a real fuse instance
- [ ] Round-trip: create → snapshot → restore → drain → destroy
- [ ] Health/readiness checks against fuse `/health`, `/ready`
- [ ] Observability around actions + SSE lifecycle
- [ ] Config docs (base URL, token, CIDR notes)
- [ ] Deployment notes
