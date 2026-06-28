# Phase 5 — Event streaming (SSE → PubSub)

Consume fuse's per-environment SSE stream and rebroadcast typed events onto
`Phoenix.PubSub` so LiveView (Phase 8) and any other subscriber can react
without polling.

## Verified facts (do not re-litigate)

**fuse SSE endpoint** (`fuse/api/sse.go`, `fuse/api/openapi.yaml`):
- `GET /v1/environments/{vmId}/events`, Bearer auth (same token), `Content-Type: text/event-stream`.
- Frame format — **no `event:` line**: `id: <128-bit hex>\ndata: {json}\n\n`.
- Keepalive comment `: keepalive\n\n` every **15s** — must be ignored.
- Payload JSON (single kind in v1): `{id, event:"state", vm_id, state, url?, error?, updated_at}`.
  - `state` ∈ `provisioning|running|draining|destroying|destroyed|failed`.
  - `destroyed`/`failed` are **terminal**, wire-only synthetic states.
- **First event on connect = snapshot of current state** (every consumer gets one event immediately).
- Stream closes cleanly (EOF) **after** delivering a terminal event.
- `404` (env gone) returned **before** SSE headers, JSON error envelope.
- `last_event_id` query param is **parsed but ignored in v1** — reconnect gets a
  fresh snapshot and silently misses transitions during the gap. Send it for
  forward-compat; build **no** resume machinery on it; document the gap.
- Single-process pub/sub on the server; 32-event per-subscriber buffer (slow
  consumers drop events). Not our problem, but note it.

**Req 0.5.18 streaming** (`deps/req/lib/req.ex:81,1287`): `into: :self` returns a
`%Req.Response{status, body: %Req.Response.Async{}}` after headers; body chunks
arrive as **process messages**. `Req.parse_message(resp, msg)` →
`{:ok, [data: bin, ...]}` / `{:ok, [:done]}` / `:unknown` (msg not ours).
`Req.cancel_async_response/1` tears down the socket.
→ **One GenServer per env owns the socket and parses in `handle_info`.**

**Infra already present**: `{Phoenix.PubSub, name: Fuse.PubSub}` in
`Fuse.Application`. `Fuse.Client.HTTP.base_options/0` already builds base_url +
bearer auth from config — reuse for the stream request.

## Module layout

```
lib/fuse/wire.ex                      # NEW: extract parse_datetime/1 (5th copy); see below
lib/fuse/event_stream.ex              # public API: watch/1, unwatch/1, subscribe helpers, topics
lib/fuse/event_stream/event.ex        # typed struct, from_wire/1, terminal?/1
lib/fuse/event_stream/sse.ex          # PURE frame parser — the keystone
lib/fuse/event_stream/consumer.ex     # GenServer, one per vm_id, owns socket
lib/fuse/event_stream/supervisor.ex   # DynamicSupervisor for consumers
lib/fuse/event_stream/source.ex       # behaviour: how a consumer opens/reads a stream
lib/fuse/event_stream/source/http.ex  # Req into: :self impl
lib/fuse/event_stream/source/fake.ex  # test impl: scripted frames as messages
```

Add to `Fuse.Application` children (after PubSub):
`{Registry, keys: :unique, name: Fuse.EventStream.Registry}` and
`Fuse.EventStream.Supervisor`.

### `Fuse.Wire` (do first)
`parse_datetime/1` is currently duplicated in Environment, Snapshot,
Snapshot.Export, Host — events make it the 5th. Extract:
```elixir
def parse_datetime(v) when is_binary(v) do
  case DateTime.from_iso8601(v) do
    {:ok, dt, _} -> dt
    {:error, _} -> nil
  end
end
def parse_datetime(_), do: nil
```
Repoint all four existing call sites; their tests already cover it.

### `Fuse.EventStream.Event`
Struct `id, kind, vm_id, state, url, error, updated_at`. `from_wire/1` maps the
JSON (note `kind` ← `"event"` key, `updated_at` via `Fuse.Wire`). `terminal?/1`
delegates to `Fuse.State.terminal?/1` (already knows destroyed/failed).

### `Fuse.EventStream.SSE` — the keystone (pure, test hard)
`parse(buffer :: binary) :: {events :: [map], rest :: binary}` where each event
is the decoded `data:` JSON map (or raise/skip on bad JSON — decide & test).
- Accumulate across chunks; a frame split mid-way stays in `rest`.
- Split on `\n\n`; within a frame read `id:`/`data:` lines; **ignore** any line
  starting with `:` (keepalive) and unknown fields.
- Multiple frames per chunk; blank-line termination; `data:` may have a leading
  space to strip (`data: {...}` → `{...}`).
This module has **no** HTTP/process dependency — exhaustive unit coverage lives here.

### `Fuse.EventStream.Source` (behaviour)
Keeps streaming **out of `Fuse.Client`** (whose `{:ok, map}` contract doesn't fit
long-lived streams). Callbacks (shape TBD during impl, sketch):
- `open(vm_id, opts) :: {:ok, handle} | {:error, Fuse.Error.t()}` — establishes
  the stream, returns after headers; `handle` carries what `handle_info` needs.
- `parse(handle, message) :: {:ok, [chunk]} | :unknown | {:error, reason}` and
  `close(handle)`.
- **HTTP impl**: `Req` with `into: :self`, base_url+bearer from
  `Fuse.Client.HTTP` config, `retry: false`. Checks `resp.status`: 200 → ok;
  non-200 → `{:error, %Fuse.Error{}}` (decode envelope if cheap, else map status).
- **Fake impl**: ignores the network; lets the test drive frames by sending the
  consumer messages it will hand back through `parse/2`. Configurable script:
  snapshot event, N transitions, then `:done`, or a simulated transport error.
- Swap via `config :fuse, :event_source, ...` (mirrors `:fuse_client`).

### `Fuse.EventStream.Consumer` (GenServer, one per vm_id)
Registered `{:via, Registry, {Fuse.EventStream.Registry, vm_id}}` (dedupe).
- `init`: `{:ok, state, {:continue, :connect}}` (don't block the supervisor).
- `handle_continue(:connect)`: `Source.open/2`. On `{:error, %Fuse.Error{}}` →
  broadcast an error/terminal signal then `{:stop, :normal}` if it's a 404
  (env gone), else schedule a backoff reconnect.
- `handle_info(msg)`: `Source.parse(handle, msg)`:
  - `{:ok, chunks}` → fold `{:data, bin}` into buffer, run `SSE.parse/1`,
    `Event.from_wire/1` each, **broadcast each**; if any event is
    `Event.terminal?/1` → broadcast then `{:stop, :normal}` (drive terminal off
    the **decoded state**, not EOF timing).
    `:done` in chunks → unexpected-EOF path (reconnect w/ backoff) **unless** a
    terminal event was already seen this connection.
  - `:unknown` → ignore (not our message).
  - `{:error, _}` → reconnect with backoff.
- **Three connect outcomes, kept distinct**:
  1. non-200 404 → stop, no reconnect (env gone).
  2. clean EOF *after* a terminal event → stop, no reconnect.
  3. unexpected EOF / transport error → reconnect, exp backoff (1→2→4…→30s cap),
     re-open with `last_event_id` (forward-compat; expect a fresh snapshot).
- `terminate`: `Source.close/1`.

### `Fuse.EventStream` (public API)
- `watch(vm_id)` → `DynamicSupervisor.start_child` (idempotent via Registry;
  `{:error, {:already_started, pid}}` → `{:ok, pid}`).
- `unwatch(vm_id)` → look up & terminate the child.
- `subscribe(vm_id)` / `subscribe_all()` → `Phoenix.PubSub.subscribe`.
- **Topics**: `"environments"` (all) + `"environment:#{vm_id}"` (one env).
- **Message**: `{:environment_event, %Event{}}`. Broadcast to **both** topics.
  (Free convention pick — stated here so Phase 8 can rely on it.)

## Watching policy
Phase 5 only exposes `watch/unwatch`. *Who* calls them (LiveView on detail-page
mount, ref-counted, idle teardown) is a **Phase 8** decision — don't build it now.

## Testing strategy (and its honest gap)
- **`SSE.parse/1`**: exhaustive & isolated — mid-frame chunk splits, multi-frame
  chunks, keepalive comments, `id:`+`data:` pairing, leading-space strip, bad
  JSON. Most real bugs live here.
- **`Event.from_wire/1`**: decode + `terminal?` for each state.
- **`Consumer`**: via the **Fake source** — `subscribe` in the test, assert
  `{:environment_event, %Event{}}` arrives, assert terminal event stops the
  consumer, assert transport-error → reconnect. No HTTP.
- **`EventStream.watch/unwatch`**: dedupe (two watches → one child), unwatch
  terminates.
- **GAP — state explicitly**: `Source.HTTP` gets **no unit coverage** in Phase 5.
  `Req.Test`'s in-process plug stub runs the plug to completion before Req sees a
  body, so it can't simulate long-lived chunked SSE + keepalives. Real-socket
  coverage rides to **Phase 10**'s `FUSE_INTEGRATION` gate (or add `Bypass` here
  if we want it sooner — decide at build time). Do **not** let the suite read as
  if the HTTP source is covered.

## Build order
1. `Fuse.Wire` + repoint 4 call sites (green suite).
2. `Event` + tests.
3. `SSE` parser + exhaustive tests.
4. `Source` behaviour + `Source.Fake`.
5. `Consumer` + Registry + tests against Fake.
6. `Supervisor` + `EventStream` public API + tests; wire into `Application`.
7. `Source.HTTP` (Req `into: :self`); note the coverage gap.

## Open decisions to confirm before coding
- **Bad-JSON in a `data:` frame**: skip-and-log vs crash-the-consumer? (lean skip+log.)
- **HTTP source coverage now (Bypass) vs Phase 10 integration gate?** (lean Phase 10.)
- **Error surfacing**: when a consumer can't connect (404/persistent failure),
  broadcast a typed `{:environment_stream_down, vm_id, reason}` so the UI can show
  it, or just stop silently? (lean broadcast a down signal.)
