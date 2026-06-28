defmodule FuseWeb.SetupHTML do
  @moduledoc "First-run setup page: create the console admin password."
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
            <h1 class="text-[18px] font-semibold tracking-tight text-ink">Welcome to Fuse</h1>
            <p class="mt-1 text-[13px] text-muted">
              Set an admin password to secure this console
            </p>
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

          <.form for={%{}} action={~p"/setup"} method="post" class="space-y-4">
            <div>
              <label for="password" class="mb-1.5 block text-[12px] font-medium text-ink">
                Admin password
              </label>
              <input
                id="password"
                type="password"
                name="password"
                autocomplete="new-password"
                autofocus
                minlength="8"
                placeholder="At least 8 characters"
                class="w-full rounded-lg border border-rail bg-canvas px-3 py-2 font-mono text-[13px] text-ink outline-none placeholder:text-muted/60 focus:border-brand focus:ring-2 focus:ring-brand/20"
              />
            </div>
            <div>
              <label for="password_confirmation" class="mb-1.5 block text-[12px] font-medium text-ink">
                Confirm password
              </label>
              <input
                id="password_confirmation"
                type="password"
                name="password_confirmation"
                autocomplete="new-password"
                placeholder="Re-enter the password"
                class="w-full rounded-lg border border-rail bg-canvas px-3 py-2 font-mono text-[13px] text-ink outline-none placeholder:text-muted/60 focus:border-brand focus:ring-2 focus:ring-brand/20"
              />
            </div>
            <button
              type="submit"
              class="w-full rounded-lg bg-brand px-3.5 py-2.5 text-[13px] font-medium text-white shadow-sm transition hover:bg-brand-strong"
            >
              Create password &amp; continue
            </button>
          </.form>
        </div>

        <p class="mt-4 text-center text-[11px] text-muted">
          This is the only account. Anyone with this password can manage the fleet.
        </p>
      </div>
    </div>
    """
  end
end
