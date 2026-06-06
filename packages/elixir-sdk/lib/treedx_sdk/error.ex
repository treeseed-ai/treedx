defmodule TreeDxSdk.Error do
  @moduledoc "TreeDX SDK error shape."
  defexception [:status, :code, :message, :details, :payload]

  def from_response(status, payload) do
    error = get_error(payload)

    %__MODULE__{
      status: status,
      code: string_value(error, "code", "service_unavailable"),
      message: string_value(error, "message", "TreeDX request failed"),
      details: map_value(error, "details"),
      payload: payload
    }
  end

  def network(message) do
    %__MODULE__{
      status: 0,
      code: "network_error",
      message: to_string(message),
      details: nil,
      payload: nil
    }
  end

  defp get_error(%{"error" => error}) when is_map(error), do: error
  defp get_error(%{error: error}) when is_map(error), do: error
  defp get_error(payload) when is_map(payload), do: payload
  defp get_error(_payload), do: %{}

  defp string_value(map, key, default) do
    case Map.get(map, key) || Map.get(map, String.to_atom(key)) do
      value when is_binary(value) -> value
      _ -> default
    end
  end

  defp map_value(map, key), do: Map.get(map, key) || Map.get(map, String.to_atom(key))
end
