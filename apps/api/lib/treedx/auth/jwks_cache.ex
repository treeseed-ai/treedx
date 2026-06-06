defmodule TreeDx.Auth.JwksCache do
  @moduledoc false
  use GenServer

  @name __MODULE__

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: @name)

  def init(state), do: {:ok, state}

  def get_key(kid, fetcher \\ &fetch_jwks/0) do
    ensure_started()
    GenServer.call(@name, {:get_key, kid, fetcher})
  end

  def reset do
    ensure_started()
    GenServer.call(@name, :reset)
  end

  def handle_call(:reset, _from, _state), do: {:reply, :ok, %{}}

  def handle_call({:get_key, kid, fetcher}, _from, state) do
    now = System.system_time(:second)
    ttl = env_int("TREEDX_JWKS_CACHE_TTL_SECONDS", 300)
    grace = env_int("TREEDX_JWKS_ROTATION_GRACE_SECONDS", 300)

    case Map.get(state, kid) do
      %{key: key, fetched_at: fetched_at} when fetched_at + ttl > now ->
        {:reply, {:ok, key}, state}

      cached ->
        case fetcher.() do
          {:ok, keys} ->
            refreshed_at = System.system_time(:second)

            new_state =
              Map.new(keys, fn key -> {key["kid"], %{key: key, fetched_at: refreshed_at}} end)

            case Map.get(new_state, kid) do
              %{key: key} ->
                {:reply, {:ok, key}, Map.merge(state, new_state)}

              nil ->
                {:reply, {:error, %{code: "invalid_token", message: "Unknown JWT key id."}},
                 Map.merge(state, new_state)}
            end

          {:error, error} ->
            if cached && cached.fetched_at + ttl + grace > now do
              {:reply, {:ok, cached.key}, state}
            else
              {:reply, {:error, error}, state}
            end
        end
    end
  end

  defp fetch_jwks do
    url = System.get_env("TREEDX_JWKS_URL")
    timeout = env_int("TREEDX_JWKS_REFRESH_TIMEOUT_MS", 2_000)

    with true <- is_binary(url) and url != "",
         {:ok, bytes} <- fetch_bytes(url, timeout),
         {:ok, %{"keys" => keys}} when is_list(keys) <- Jason.decode(bytes) do
      {:ok, keys}
    else
      false -> {:error, %{code: "auth_not_configured", message: "TREEDX_JWKS_URL is required."}}
      {:ok, _} -> malformed()
      {:error, error} when is_map(error) -> {:error, error}
      _ -> malformed()
    end
  end

  defp fetch_bytes("file://" <> path, _timeout), do: File.read(path)

  defp fetch_bytes(url, timeout) do
    :inets.start()
    :ssl.start()
    charlist = String.to_charlist(url)
    opts = [timeout: timeout]

    case :httpc.request(:get, {charlist, []}, opts, body_format: :binary) do
      {:ok, {{_, 200, _}, _headers, body}} ->
        {:ok, body}

      {:ok, {{_, status, _}, _headers, _body}} ->
        {:error, %{code: "invalid_token", message: "JWKS fetch failed with HTTP #{status}."}}

      {:error, reason} ->
        {:error, %{code: "invalid_token", message: "JWKS fetch failed: #{inspect(reason)}."}}
    end
  end

  defp malformed do
    TreeDx.Audit.append("auth.jwks_refresh_failed", %{
      status: "error",
      data: %{reason: "malformed_jwks"}
    })

    {:error, %{code: "invalid_token", message: "Malformed JWKS."}}
  end

  defp ensure_started do
    case Process.whereis(@name) do
      nil -> {:ok, _pid} = start_link([])
      _pid -> :ok
    end
  end

  defp env_int(name, default) do
    case Integer.parse(System.get_env(name) || "") do
      {value, _} when value >= 0 -> value
      _ -> default
    end
  end
end
