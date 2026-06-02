defmodule TreeDb.Audit.Event do
  @moduledoc false

  def new(event_type, attrs) do
    %{
      eventType: event_type,
      actorId: get(attrs, :actor_id),
      tenantId: get(attrs, :tenant_id),
      repoId: get(attrs, :repo_id),
      nodeId: get(attrs, :node_id) || System.get_env("TREEDB_NODE_ID") || "node_local",
      workspaceId: get(attrs, :workspace_id),
      operation: get(attrs, :operation),
      status: get(attrs, :status),
      requestId: get(attrs, :request_id),
      requestedScope: get(attrs, :requested_scope),
      effectiveScope: get(attrs, :effective_scope),
      data: sanitize_data(get(attrs, :data) || %{})
    }
  end

  def sanitize_data(data) when is_map(data) do
    data
    |> Enum.reject(fn {key, _value} -> sensitive_key?(key) end)
    |> Enum.map(fn
      {key, value} when key in [:command, "command", :cmd, "cmd"] ->
        {key, sanitize_command(value)}

      pair ->
        pair
    end)
    |> Map.new()
  end

  def sanitize_data(_), do: %{}

  def sanitize_command(command) when is_binary(command) do
    command
    |> String.replace(~r/(Bearer|token|password|secret)=\S+/i, "\\1=<redacted>")
    |> String.slice(0, 500)
  end

  def sanitize_command(_), do: nil

  defp sensitive_key?(key) do
    key
    |> to_string()
    |> String.downcase()
    |> then(&(&1 in ["content", "stdout", "stderr", "access_token", "accesstoken", "token"]))
  end

  defp get(attrs, key), do: Map.get(attrs, key) || Map.get(attrs, to_string(key))
end
