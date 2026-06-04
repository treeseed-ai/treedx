defmodule TreeDb.Cache do
  @moduledoc false

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

  def get_or_load(table, key, ttl_ms, max_entries, loader) do
    now = System.monotonic_time(:millisecond)

    case lookup(table, key, now, ttl_ms) do
      {:ok, value} ->
        {:ok, value}

      :miss ->
        with {:ok, value} <- loader.() do
          put(table, key, value, now, max_entries)
          {:ok, value}
        end
    end
  end

  def put(
        table,
        key,
        value,
        inserted_at \\ System.monotonic_time(:millisecond),
        max_entries \\ 256
      ) do
    if table_exists?(table) do
      :ets.insert(table, {key, inserted_at, value})
      evict(table, max_entries)
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

  def ensure_table(table) do
    if :ets.whereis(table) == :undefined do
      :ets.new(table, [:named_table, :public, read_concurrency: true])
    end

    :ok
  end

  defp lookup(table, key, now, ttl_ms) do
    if table_exists?(table) do
      case :ets.lookup(table, key) do
        [{^key, inserted_at, value}] when now - inserted_at <= ttl_ms ->
          {:ok, value}

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

  defp evict(_table, max_entries) when max_entries <= 0, do: :ok

  defp evict(table, max_entries) do
    size = :ets.info(table, :size) || 0

    if size > max_entries do
      table
      |> :ets.tab2list()
      |> Enum.sort_by(fn {_key, inserted_at, _value} -> inserted_at end)
      |> Enum.take(size - max_entries)
      |> Enum.each(fn {key, _inserted_at, _value} -> :ets.delete(table, key) end)
    end

    :ok
  end

  defp table_exists?(table), do: :ets.whereis(table) != :undefined
end
