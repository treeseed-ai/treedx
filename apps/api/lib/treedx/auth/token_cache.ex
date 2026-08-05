defmodule TreeDx.Auth.TokenCache do
  @moduledoc false
  use GenServer

  alias TreeDx.Cache

  @table __MODULE__

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def init(state) do
    Cache.ensure_table(@table)
    {:ok, state}
  end

  def get_dev_record(credential_digest, loader) do
    Cache.get_or_load(
      @table,
      {:dev_token, credential_digest},
      Cache.int_env("TREEDX_AUTH_TOKEN_CACHE_TTL_MS", 5_000),
      Cache.int_env("TREEDX_AUTH_TOKEN_CACHE_MAX_ENTRIES", 4_096),
      loader
    )
  end

  def reset, do: Cache.reset(@table)
end
