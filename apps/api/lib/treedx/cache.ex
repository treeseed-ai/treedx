defmodule TreeDx.Cache do
  @moduledoc false

  alias TreeDx.Observability.Metrics

  def enabled?(name, default \\ true) do
    case System.get_env(name) do
      nil -> default
      value -> value in ["true", "1", "yes", "on"]
    end
  end

  def int_env(name, default) do
    case Integer.parse(System.get_env(name, "#{default}")) do
      {value, _} when value > 0 -> value
      _ -> default
    end
  end

  def get_or_load(table, key, ttl_ms, max_entries, loader),
    do: get_or_load(table, key, ttl_ms, max_entries, nil, loader)

  def get_or_load(table, key, ttl_ms, max_entries, max_bytes, loader) do
    now = System.monotonic_time(:millisecond)

    case lookup(table, key, now, ttl_ms) do
      {:ok, value} ->
        Metrics.incr("treedx_cache_hits_total", %{cache: cache_name(table)})
        {:ok, value}

      :miss ->
        Metrics.incr("treedx_cache_misses_total", %{cache: cache_name(table)})

        with {:ok, value} <- loader.() do
          put(table, key, value, now, max_entries, max_bytes)
          {:ok, value}
        end
    end
  end

  def put(
        table,
        key,
        value,
        inserted_at \\ System.monotonic_time(:millisecond),
        max_entries \\ 256,
        max_bytes \\ nil
      ) do
    if table_exists?(table) do
      approx_bytes = approx_bytes(value)
      :ets.insert(table, {key, inserted_at, inserted_at, approx_bytes, value})
      evict(table, max_entries, max_bytes)
    end

    :ok
  end

  def delete(table, key) do
    if table_exists?(table), do: :ets.delete(table, key)
    :ok
  end

  def reset(table) do
    if table_exists?(table), do: :ets.delete_all_objects(table)
    :ok
  end

  def stats(table) do
    if table_exists?(table) do
      entries = :ets.tab2list(table)

      %{
        entries: length(entries),
        approx_bytes: Enum.sum(Enum.map(entries, &entry_bytes/1))
      }
    else
      %{entries: 0, approx_bytes: 0}
    end
  end

  def evict(table, limits) when is_map(limits) do
    evict(table, Map.get(limits, :max_entries), Map.get(limits, :max_bytes))
  end

  def ensure_table(table) do
    if :ets.whereis(table) == :undefined do
      :ets.new(table, [:named_table, :public, read_concurrency: true])
    end

    :ok
  end

  defp lookup(table, key, now, ttl_ms) do
    if table_exists?(table) do
      case :ets.lookup(table, key) do
        [{^key, inserted_at, _last_accessed_at, approx_bytes, value}]
        when now - inserted_at <= ttl_ms ->
          :ets.insert(table, {key, inserted_at, now, approx_bytes, value})
          {:ok, value}

        [{^key, inserted_at, value}] when now - inserted_at <= ttl_ms ->
          :ets.insert(table, {key, inserted_at, now, approx_bytes(value), value})
          {:ok, value}

        [{^key, _inserted_at, _last_accessed_at, _approx_bytes, _value}] ->
          :ets.delete(table, key)
          :miss

        [{^key, _inserted_at, _value}] ->
          :ets.delete(table, key)
          :miss

        [] ->
          :miss
      end
    else
      :miss
    end
  end

  defp evict(table, max_entries, max_bytes) do
    evict_by_entries(table, max_entries)
    evict_by_bytes(table, max_bytes)
    publish_stats(table)
    :ok
  end

  defp evict_by_entries(_table, nil), do: :ok
  defp evict_by_entries(_table, max_entries) when max_entries <= 0, do: :ok

  defp evict_by_entries(table, max_entries) do
    size = :ets.info(table, :size) || 0

    if size > max_entries do
      evicted = size - max_entries

      table
      |> :ets.tab2list()
      |> Enum.sort_by(&entry_sort_key/1)
      |> Enum.take(evicted)
      |> Enum.each(fn entry -> :ets.delete(table, elem(entry, 0)) end)

      Metrics.incr(
        "treedx_cache_evictions_total",
        %{cache: cache_name(table), reason: "entries"},
        evicted
      )
    end

    :ok
  end

  defp evict_by_bytes(_table, nil), do: :ok
  defp evict_by_bytes(_table, max_bytes) when max_bytes <= 0, do: :ok

  defp evict_by_bytes(table, max_bytes) do
    entries = :ets.tab2list(table)
    total = Enum.sum(Enum.map(entries, &entry_bytes/1))

    if total > max_bytes do
      {evicted, _bytes} =
        entries
        |> Enum.sort_by(&entry_sort_key/1)
        |> Enum.reduce_while({0, total}, fn entry, {count, bytes} ->
          if bytes <= max_bytes do
            {:halt, {count, bytes}}
          else
            :ets.delete(table, elem(entry, 0))
            {:cont, {count + 1, bytes - entry_bytes(entry)}}
          end
        end)

      Metrics.incr(
        "treedx_cache_evictions_total",
        %{cache: cache_name(table), reason: "bytes"},
        evicted
      )
    end

    :ok
  end

  defp publish_stats(table) do
    stats = stats(table)
    labels = %{cache: cache_name(table)}
    Metrics.put_gauge("treedx_cache_entries", stats.entries, labels)
    Metrics.put_gauge("treedx_cache_approx_bytes", stats.approx_bytes, labels)
  end

  defp approx_bytes(value), do: :erlang.external_size(value)

  defp entry_bytes({_key, _inserted_at, _last_accessed_at, approx_bytes, _value}),
    do: approx_bytes

  defp entry_bytes({_key, _inserted_at, value}), do: approx_bytes(value)

  defp entry_sort_key({_key, inserted_at, last_accessed_at, _approx_bytes, _value}),
    do: {last_accessed_at, inserted_at}

  defp entry_sort_key({_key, inserted_at, _value}), do: {inserted_at, inserted_at}

  defp cache_name(table), do: table |> Module.split() |> List.last() |> Macro.underscore()

  defp table_exists?(table), do: :ets.whereis(table) != :undefined
end
