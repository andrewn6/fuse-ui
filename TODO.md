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

- [x] `Fuse.Environments.list/1` (filters: task_id, state, host_id)
- [x] `Fuse.Environments.get/1`
- [x] `Fuse.Environments.create/1` (task*id, spec, secrets, startup_script, gateway*\*)
- [x] `Fuse.Environments.drain/1`
- [x] `Fuse.Environments.rotate_token/1`
- [x] `Fuse.Environments.destroy/1`
- [x] Decode wire JSON → `Fuse.Environments.Environment` struct
- [x] Context tests against the fake client

## Phase 3 — Snapshots context

- [x] `Fuse.Snapshots.create/2` (vm_id + comment/mode/retention/metadata/export_ref)
- [x] `Fuse.Snapshots.list/1` (filters: vm_id, task_id, tenant_id, state)
- [x] `Fuse.Snapshots.get/1`
- [x] `Fuse.Snapshots.restore/1`
- [x] `Fuse.Snapshots.delete/1`
- [x] Decode → `Fuse.Snapshots.Snapshot` struct (incl. `exports`)
- [x] Context tests

## Phase 4 — Hosts context

- [x] `Fuse.Hosts.register/1`, `list/0`, `get/1`, `cordon/1`, `uncordon/1`, `remove/1`
- [x] Decode → `Fuse.Hosts.Host` struct (capacity vs allocated)
- [x] Context tests

## Phase 5 — Event streaming (SSE → PubSub)

- [x] `Fuse.EventStream` — consume `GET /v1/environments/{id}/events`
- [x] Supervised consumer per watched environment (DynamicSupervisor + Registry)
- [x] Parse SSE frames → typed events (`SSE` parser + `Event` struct)
- [x] Broadcast to `Phoenix.PubSub` topics (`environments`, `environment:{id}`)
- [x] Reconnect/backoff handling (exp backoff; terminal/404 stop, transient reconnect)
- [x] Fake event source for tests (`Source.Fake`)
- [x] `Source.HTTP.open/2` status branches covered (404/409/500/403 + 2xx async shape)
- [ ] ~~`Source.HTTP` live streaming/parse path~~ — deferred to Phase 10 integration
      gate (Req's in-process plug can't simulate long-lived chunked SSE); see `PHASE5.md`

## Phase 6 — Local mirror (cache/audit)

Decision: the proxy stays authoritative (fuse owns truth), but we **also** keep an
Ecto-mirrored read model as a best-effort, gated cache — never on the request's
critical path. `Fuse.Mirror`/`Fuse.Audit` writes are swallowed on failure and
disabled in `test`. The orphaned `redis_instances` scaffolding is left untouched.

- [x] Decide: thin proxy vs. Ecto-mirrored read model (both — authoritative proxy + best-effort mirror)
- [x] Add `mirror_environments` / `mirror_snapshots` cache tables (+ `audit_log`) migration & schemas
- [x] Upsert write-through from list/get responses and patch from PubSub events (`Fuse.Mirror.Listener`)
- [x] Audit log of actions (who/what/when) — `Fuse.Audit`, recorded at the context choke point

## Phase 7 — REST passthrough API

- [x] `/api/v1` router scope (`scope "/api/v1", FuseWeb.API`, `pipe_through :api`)
- [x] `EnvironmentController` (index/show/create/destroy + `?action=drain|rotate-token`)
- [x] `SnapshotController` (index/show/create/destroy + `?action=restore`; create nested under env)
- [x] `HostController` (index/show/register/destroy + `?action=cordon|uncordon`)
- [x] JSON error rendering — `FallbackController` + `API.ErrorJSON`, `{"errors":{code,message,details}}`,
      code→status map (404/409/422/503/500/502); responses use `{"data": ...}` wrapper
- [x] Controller tests (happy paths + 404/422/400/204/201/200, incl. empty/malformed-body edge cases)

Conventions (decided this phase): action routing mirrors fuse's `?action=`; responses use the
Phoenix `{"data": ...}` / `{"errors": ...}` wrapper; errors keep fuse's `code` (not just `detail`).

## Phase 8 — LiveView dashboard

Design system in place: `@theme` tokens (canvas/surface/rail/ink/muted/brand + state colors)

- Inter/JetBrains Mono in `assets/css/app.css`; `Layouts.console/1` shell (sidebar) +
  `Layouts.nav_item/1`. Root → `/environments`. Accuracy note from fuse scout: **no per-env
  token** (mock's `tok_…` is cosmetic), rotate-token is 204, counts/version/activity/workspace
  are app-side not fuse-backed.

* [x] Environments list + state badges + host column + state-filter pills (`EnvironmentLive.Index`)
* [x] Loading + error states (error banner when fuse unreachable) ; LiveView test (HTTP+plug stub)
* [x] Create-environment form (plan presets) + modal ; drain/destroy/rotate-token actions + confirm modals
* [x] Snapshots panel (filters, restore/delete confirms) (`SnapshotLive.Index`)
* [x] Hosts panel (capacity used/total, cordon/uncordon/remove, host-onboarding empty state + register modal)
* [x] Activity (honest empty state — fuse has no activity API) + Settings (connection info; never prints token)
* [x] Shared `Layouts.modal/1` (show_modal/hide_modal) + `Layouts.badge/1`
* [x] Login page (browser session: `CONTROL_PLANE_TOKEN` → Phoenix session) + `AuthHook` gate + logout
* [x] Environment detail (spec, URL, live event log via PubSub, ref-counted `watch`) — `EnvironmentLive.Show`
* [x] Command palette (⌘K) ; copy-to-clipboard hook ; dark theme (Phoenix colocated hooks + CSS tokens)
* [x] Workspace switcher — dropped (fuse has no workspaces); none rendered

Built via `phase8-screens` workflow (Hosts/Snapshots/Activity/Settings + modals); workflow was
interrupted after Screens, completed by hand (routes/nav wired, 2 bugs fixed: settings badge call,
host_live `not @load_error` crash on empty state). All green: 266 tests.

## Phase 9 — Auth & safety

- [x] Fuse Bearer token from runtime config / secrets (never logged) — outbound `FUSE_TOKEN`
- [x] App-side auth for all `/api/v1` (inbound) — `FuseWeb.Plugs.ApiAuth`: single static bearer token
      (`CONTROL_PLANE_TOKEN`), constant-time compare, case-sensitive `Bearer `, `nil`/`""` = insecure no-op
      (mirrors fuse), non-binary misconfig = fail loud/closed; 401 `{"errors":{code:"unauthorized"}}`.
      Adversarially reviewed (5 lenses); findings applied.
- [x] Prod safety: boot-time warning when `CONTROL_PLANE_TOKEN` unset in prod
      (`Fuse.Application.warn_if_insecure_prod/0`; non-fatal — boots open, logs loudly)
- [x] Token model decided: single shared static token (not per-client named keys)
- [x] Validate resource bounds before forwarding to fuse (`Fuse.Bounds`, wired into `Environments.create`)
- [x] Confirm-before-destroy on drain/destroy/restore (all destructive actions go through confirm modals)
- [x] Rate limit write endpoints (`FuseWeb.Plugs.RateLimiter` + `FuseWeb.RateLimiter`; per-IP fixed window, opt-in)
- [x] CIDR allowlist plug (`FuseWeb.Plugs.CidrAllowlist`, `CONTROL_PLANE_ALLOWED_CIDRS`; v4 + v6, opt-in)

## Phase 10 — Integration & hardening

- [x] `:integration`-tagged gate hitting a real fuse instance (`mix test --include integration`)
- [x] Round-trip: create → snapshot → restore → drain → destroy (`test/integration/fuse_round_trip_test.exs`)
- [x] Health/readiness checks against fuse `/health`, `/ready` (`Fuse.Health` + app `/healthz`, `/readyz`)
- [x] Observability around actions + SSE lifecycle (`[:fuse, :action]` telemetry; SSE/HTTP structured logs)
- [x] Config docs (base URL, token, CIDR, rate-limit notes) — README
- [x] Deployment notes — README (release, env vars, migrations, TLS/proxy, probes)
