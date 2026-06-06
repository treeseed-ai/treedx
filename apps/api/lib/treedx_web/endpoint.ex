defmodule TreeDxWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :treedx

  plug(Plug.RequestId)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])

  plug(Plug.Parsers,
    parsers: [:json],
    pass: ["application/json", "application/octet-stream"],
    json_decoder: Jason
  )

  plug(TreeDxWeb.Router)
end
