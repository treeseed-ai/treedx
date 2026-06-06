import Config

if config_env() == :prod do
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :treedx, TreeDxWeb.Endpoint,
    http: [ip: {0, 0, 0, 0}, port: port],
    url: [host: System.get_env("PHX_HOST") || "localhost", port: port],
    server: true
end
