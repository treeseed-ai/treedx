import Config

config :treedx,
  namespace: TreeDx

config :treedx, TreeDx.Native,
  crate: :treedx_native,
  path: "native/treedx_native",
  mode: if(config_env() == :prod, do: :release, else: :debug)

config :treedx, TreeDxWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  url: [host: "localhost"],
  render_errors: [
    formats: [json: TreeDxWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: nil,
  live_view: [signing_salt: "treedx"]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

import_config "#{config_env()}.exs"
