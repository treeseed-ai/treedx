defmodule TreeDx.Observability.JsonLogFormatter do
  @moduledoc false

  alias TreeDx.Observability.Scrubber

  def format(level, message, timestamp, metadata) do
    payload =
      metadata
      |> Enum.into(%{})
      |> drop_forbidden()
      |> normalize_keys()
      |> Scrubber.scrub()
      |> Map.merge(%{
        timestamp: format_timestamp(timestamp),
        level: to_string(level),
        message: IO.iodata_to_binary(message)
      })

    [Jason.encode!(payload), "\n"]
  rescue
    _ -> [inspect(message), "\n"]
  end

  defp format_timestamp({date, {hour, minute, second, millisecond}}) do
    {{year, month, day}, _} = {date, nil}

    NaiveDateTime.new!(year, month, day, hour, minute, second, {millisecond * 1000, 3})
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.to_iso8601()
  end

  defp drop_forbidden(metadata) do
    Map.drop(metadata, [
      :params,
      "params",
      :body,
      "body",
      :request_body,
      "request_body",
      :requestBody,
      "requestBody",
      :headers,
      "headers",
      :authorization,
      "authorization",
      :query_string,
      "query_string",
      :queryString,
      "queryString",
      :stdout,
      "stdout",
      :stderr,
      "stderr"
    ])
  end

  defp normalize_keys(metadata) do
    metadata
    |> Enum.map(fn {key, value} -> {normalize_key(key), value} end)
    |> Enum.into(%{})
  end

  defp normalize_key(:request_id), do: "requestId"
  defp normalize_key("request_id"), do: "requestId"
  defp normalize_key(:actor_id), do: "actorId"
  defp normalize_key("actor_id"), do: "actorId"
  defp normalize_key(:tenant_id), do: "tenantId"
  defp normalize_key("tenant_id"), do: "tenantId"
  defp normalize_key(:repo_id), do: "repoId"
  defp normalize_key("repo_id"), do: "repoId"
  defp normalize_key(:workspace_id), do: "workspaceId"
  defp normalize_key("workspace_id"), do: "workspaceId"
  defp normalize_key(:duration_ms), do: "durationMs"
  defp normalize_key("duration_ms"), do: "durationMs"
  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key), do: to_string(key)
end
