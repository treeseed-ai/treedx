defmodule TreeDb.Audit do
  @moduledoc false

  alias TreeDb.Audit.Event

  def append(event_type, attrs \\ %{}) do
    TreeDb.Store.append_audit_event(Event.new(event_type, attrs))
  end

  def append_auth(event_type, attrs, status, data \\ %{}) do
    append(event_type, Map.merge(Map.new(attrs), %{status: status, data: data}))
  end

  def append_policy(event_type, attrs), do: append(event_type, attrs)

  def list(query, principal) do
    with {:ok, _scope} <-
           TreeDb.Capabilities.require_capability(principal, "audit:read", query["repoId"]) do
      limit = query["limit"] || 100

      TreeDb.Store.list_audit_events(%{
        actorId: query["actorId"],
        tenantId: query["tenantId"],
        repoId: query["repoId"],
        eventType: query["eventType"],
        limit: limit
      })
      |> case do
        {:ok, events} ->
          {:ok,
           %{events: events, page: %{limit: min(coerce_int(limit, 100), 500), hasMore: false}}}

        other ->
          other
      end
    end
  end

  defp coerce_int(value, _default) when is_integer(value), do: value

  defp coerce_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      _ -> default
    end
  end

  defp coerce_int(_value, default), do: default
end
