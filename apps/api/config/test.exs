import Config

config :treedx, TreeDxWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  server: false,
  secret_key_base: String.duplicate("b", 64)

config :logger, level: :warning

config :treedx, data_dir: Path.join(System.tmp_dir!(), "treedx-test-data")
