defmodule TreeDb.Graph.RefreshCoordinator do
  @moduledoc false
  use GenServer

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def init(_opts), do: {:ok, %{inflight: %{}}}

  def run(ctx, params, previous, refresh_plan, fun) do
    key = key(ctx, params, refresh_plan)

    if reusable_manifest?(previous, ctx, params, refresh_plan) do
      {:cached, previous}
    else
      timeout = timeout_ms()

      case GenServer.call(__MODULE__, {:start, key}, timeout + 1_000) do
        :run ->
          result = fun.()
          GenServer.cast(__MODULE__, {:finish, key, result})
          result

        {:wait, ref} ->
          receive do
            {^ref, result} -> result
          after
            timeout ->
              if is_map(previous), do: {:cached_stale, previous}, else: fun.()
          end
      end
    end
  end

  def handle_call({:start, key}, from, state) do
    case state.inflight do
      %{^key => waiters} ->
        ref = make_ref()

        {:reply, {:wait, ref},
         %{state | inflight: Map.put(state.inflight, key, [{from, ref} | waiters])}}

      _ ->
        {:reply, :run, %{state | inflight: Map.put(state.inflight, key, [])}}
    end
  end

  def handle_cast({:finish, key, result}, state) do
    {waiters, inflight} = Map.pop(state.inflight, key, [])
    Enum.each(waiters, fn {{pid, _tag}, ref} -> send(pid, {ref, result}) end)
    {:noreply, %{state | inflight: inflight}}
  end

  defp reusable_manifest?(manifest, ctx, params, refresh_plan) when is_map(manifest) do
    params["forceFull"] != true and refresh_plan.mode == "full" and
      refresh_plan.fallback_reason == nil and refresh_plan.stale != true and
      manifest["commitSha"] == ctx.resolved_ref
  end

  defp reusable_manifest?(_manifest, _ctx, _params, _refresh_plan), do: false

  defp key(ctx, params, refresh_plan) do
    {
      ctx.repo["id"],
      ctx.ref,
      ctx.resolved_ref,
      params["paths"] || ["**"],
      params["changedPaths"] || [],
      params["forceFull"],
      refresh_plan.mode
    }
  end

  defp timeout_ms do
    case Integer.parse(System.get_env("TREEDB_GRAPH_REFRESH_DEDUPE_TIMEOUT_MS", "120000")) do
      {value, _} when value > 0 -> value
      _ -> 120_000
    end
  end
end
