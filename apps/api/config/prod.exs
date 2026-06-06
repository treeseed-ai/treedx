import Config

config :treedx, TreeDxWeb.Endpoint,
  server: true,
  secret_key_base: System.get_env("SECRET_KEY_BASE") || String.duplicate("c", 64)

config :logger, :console,
  format: {TreeDx.Observability.JsonLogFormatter, :format},
  metadata: :all
