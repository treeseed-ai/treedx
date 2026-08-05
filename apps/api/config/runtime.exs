import Config

if config_env() == :prod do
  port = String.to_integer(System.get_env("PORT") || "4000")

  log_level =
    case String.downcase(System.get_env("TREEDX_LOG_LEVEL") || "warning") do
      "debug" -> :debug
      "info" -> :info
      "notice" -> :notice
      "warning" -> :warning
      "error" -> :error
      "critical" -> :critical
      "alert" -> :alert
      "emergency" -> :emergency
      _ -> :warning
    end

  config :treedx, TreeDxWeb.Endpoint,
    http: [ip: {0, 0, 0, 0}, port: port],
    url: [host: System.get_env("PHX_HOST") || "localhost", port: port],
    server: true

  config :logger, level: log_level
end
