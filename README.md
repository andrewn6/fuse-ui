# Fuse Control Plane

A Phoenix app that drives the [**fuse**](../fuse) orchestrator over its REST API:
provision / drain / destroy microVM environments, manage snapshots, watch hosts,
and surface everything in a live dashboard. fuse owns the truth; this app is a
typed client, a local read-model mirror, and a UI.

It exposes three surfaces:

- **Dashboard** (`/`) — a LiveView console (environments, hosts, snapshots,
  activity, settings) with a live event log fed by fuse's SSE stream.
- **REST passthrough** (`/api/v1`) — a thin, authenticated proxy mirroring fuse's
  routes and error envelope.
- **Health probes** (`/healthz`, `/readyz`) — unauthenticated, for orchestrators.

## Running locally

```sh
mix setup            # deps, db, assets
mix phx.server       # http://localhost:4000
```

Point it at a fuse instance with `FUSE_BASE_URL` (defaults to
`http://localhost:8080` in dev). Run the tests with `mix test`.

## Configuration

All configuration is via environment variables (wired in `config/runtime.exs`).

### Talking to fuse (outbound)

| Variable        | Default                 | Purpose                                  |
| --------------- | ----------------------- | ---------------------------------------- |
| `FUSE_BASE_URL` | `http://localhost:8080` | fuse REST base URL.                      |
| `FUSE_TOKEN`    | _(none)_                | Bearer token sent to fuse. Never logged. |

### Inbound access control

These mirror fuse's own access model. Each is **opt-in**: unset = no-op (open),
so dev/test run without configuration. Set them in production.

| Variable                       | Purpose                                                                                                                  |
| ------------------------------ | ------------------------------------------------------------------------------------------------------------------------ |
| `CONTROL_PLANE_TOKEN`          | Single shared bearer token required by `/api/v1` and the dashboard login. Unset = unauthenticated.                       |
| `CONTROL_PLANE_ALLOWED_CIDRS`  | Comma-separated CIDRs allowed to reach `/api/v1` (e.g. `10.0.0.0/8,192.168.1.0/24`). Unset = open to all. IPv4 and IPv6. |
| `CONTROL_PLANE_RATE_LIMIT`     | Max **write** requests per IP per window. Unset = unthrottled.                                                           |
| `CONTROL_PLANE_RATE_WINDOW_MS` | Rate-limit window in ms (default `60000`).                                                                               |

> Behind a load balancer, put `RemoteIp` (or equivalent) ahead of the app so the
> CIDR allowlist and rate limiter see the real client IP, not the proxy.

### Resource bounds

`Fuse.Bounds` rejects oversized create requests before they reach fuse. Tune the
caps in `config/config.exs` (`config :fuse, Fuse.Bounds, max_cpus: ..., ...`); a
`nil` cap means "no limit". Defaults are generous (64 vCPU, 256 GB RAM, 4 TB
disk, 7-day runtime).

### Local mirror & audit log

`Fuse.Mirror` keeps a local SQLite read-model of environments/snapshots
(write-through from list/get plus SSE events), and `Fuse.Audit` records every
mutating action (who/what/when) and emits a `[:fuse, :action]` telemetry event.
Both are best-effort (a cache/audit write never breaks a request) and toggled in
`config/config.exs` (`config :fuse, Fuse.Mirror, enabled: ...` /
`config :fuse, Fuse.Audit, enabled: ...`). Disabled in `test`.

### Phoenix runtime (production)

| Variable          | Required | Purpose                                                     |
| ----------------- | -------- | ----------------------------------------------------------- |
| `DATABASE_PATH`   | yes      | SQLite db path (mirror + audit), e.g. `/etc/fuse/fuse.db`.  |
| `SECRET_KEY_BASE` | yes      | Cookie/session signing. Generate with `mix phx.gen.secret`. |
| `PHX_HOST`        | yes      | Public hostname (used for URL generation).                  |
| `PORT`            | no       | HTTP listen port (default `4000`).                          |
| `PHX_SERVER`      | release  | Set `true` to start the web server in a release.            |

## Health probes

- `GET /healthz` — liveness: `200 {"status":"ok"}` whenever the app is up.
- `GET /readyz` — readiness: `200` when fuse is reachable and ready; `503`
  (`degraded`/`unreachable`) otherwise, with fuse's status echoed. Probes fuse's
  `/ready`; `Fuse.Health.liveness/0` additionally probes fuse's `/health`.

## Tests

```sh
mix test                            # unit + LiveView + controller tests
mix test --include integration \    # real-fuse round trip (create -> snapshot ->
  # with FUSE_BASE_URL / FUSE_TOKEN set   restore -> drain -> destroy)
```

Integration tests (tagged `:integration`) hit a real fuse and are excluded by
default — see `test/integration/fuse_round_trip_test.exs`.

## Deployment

This is a standard Phoenix + SQLite app deployed as an OTP release.

1. **Build a release**

   ```sh
   MIX_ENV=prod mix release
   ```

2. **Required env** (see Configuration): `DATABASE_PATH`, `SECRET_KEY_BASE`,
   `PHX_HOST`, `FUSE_BASE_URL`, `FUSE_TOKEN`, `PHX_SERVER=true`. Set the inbound
   controls (`CONTROL_PLANE_TOKEN`, and ideally `CONTROL_PLANE_ALLOWED_CIDRS` and
   a rate limit) — the app boots without them but logs a loud warning in prod
   because `/api/v1` is then unauthenticated.

3. **Migrations** run automatically on release boot (`Ecto.Migrator` in the
   supervision tree when `RELEASE_NAME` is set), creating the mirror/audit tables
   at `DATABASE_PATH`. Ensure that path is on writable, persistent storage.

4. **TLS / reverse proxy**: terminate TLS at a proxy (nginx/Caddy/ALB) or enable
   `force_ssl` + `https` on the endpoint (see commented config in
   `config/runtime.exs`). Forward the real client IP (`X-Forwarded-For` +
   `RemoteIp`) so the CIDR allowlist and rate limiter work.

5. **Probes**: wire your orchestrator's liveness probe to `/healthz` and its
   readiness probe to `/readyz`.

See the [Phoenix deployment guides](https://hexdocs.pm/phoenix/deployment.html)
for release packaging details.
