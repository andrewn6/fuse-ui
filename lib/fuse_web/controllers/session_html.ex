defmodule FuseWeb.SessionHTML do
  @moduledoc "Login page for the console."
  use FuseWeb, :html

  attr :error, :string, default: nil

  def new(assigns) do
    ~H"""
    <div class="flex min-h-screen items-center justify-center bg-canvas px-4">
      <div class="w-full max-w-sm">
        <div class="mb-6 flex flex-col items-center gap-3">
          <div class="flex size-11 items-center justify-center rounded-xl bg-brand text-white shadow-sm">
            <.icon name="hero-bolt-solid" class="size-6" />
          </div>
          <div class="text-center">
            <h1 class="text-[18px] font-semibold tracking-tight text-ink">Fuse Console</h1>
            <p class="mt-1 text-[13px] text-muted">Sign in with your control-plane token</p>
          </div>
        </div>

        <div class="rounded-2xl border border-rail bg-surface p-6 shadow-sm">
          <div
            :if={@error}
            class="mb-4 flex items-start gap-2 rounded-lg border border-bad/30 bg-bad-soft px-3 py-2.5 text-[12px] text-bad"
          >
            <.icon name="hero-exclamation-triangle" class="mt-px size-4 shrink-0" />
            <span>{@error}</span>
          </div>

          <.form for={%{}} action={~p"/login"} method="post" class="space-y-4">
            <div>
              <label for="token" class="mb-1.5 block text-[12px] font-medium text-ink">
                Control-plane token
              </label>
              <input
                id="token"
                type="password"
                name="token"
                autocomplete="current-password"
                autofocus
                placeholder="••••••••••••••••"
                class="w-full rounded-lg border border-rail bg-canvas px-3 py-2 font-mono text-[13px] text-ink outline-none placeholder:text-muted/60 focus:border-brand focus:ring-2 focus:ring-brand/20"
              />
            </div>
            <button
              type="submit"
              class="w-full rounded-lg bg-brand px-3.5 py-2.5 text-[13px] font-medium text-white shadow-sm transition hover:bg-brand-strong"
            >
              Sign in
            </button>
          </.form>
        </div>

        <p class="mt-4 text-center text-[11px] text-muted">
          The token is set via <code class="font-mono">CONTROL_PLANE_TOKEN</code>.
        </p>
      </div>
    </div>
    """
  end
end
