defmodule TreeDx.Capabilities do
  @moduledoc false

  @canonical [
    "repos:read",
    "repos:write",
    "remotes:read",
    "remotes:write",
    "files:read",
    "files:write",
    "files:delete",
    "files:search",
    "graph:refresh",
    "graph:query",
    "workspace:create",
    "workspace:exec:read_only",
    "workspace:exec:verification",
    "workspace:exec:write_limited",
    "git:read",
    "git:diff",
    "git:commit",
    "git:fetch",
    "git:push",
    "snapshot:build",
    "artifact:export",
    "registry:read",
    "registry:write",
    "mirror:read",
    "mirror:write",
    "migration:read",
    "migration:write",
    "query:federated",
    "federation:read",
    "federation:write",
    "federation:trust",
    "federation:sync",
    "policy:read",
    "policy:write",
    "audit:read"
  ]

  def canonical, do: @canonical

  def required!(nil),
    do: {:error, %{code: "authentication_required", message: "Authentication required."}}

  def required!(principal), do: {:ok, principal}

  def effective_scope(principal, repo_id \\ nil, opts \\ [])

  def effective_scope(nil, repo_id, opts) do
    if Keyword.get(opts, :allow_dev_default, false) and TreeDx.Auth.mode() == "dev" do
      with {:ok, principal} <- TreeDx.Auth.dev_principal() do
        effective_scope(principal, repo_id, [])
      end
    else
      {:error, %{code: "authentication_required", message: "Authentication required."}}
    end
  end

  def effective_scope(principal, repo_id, _opts) do
    actor_id = principal["actorId"] || principal[:actorId] || principal[:actor_id]

    with {:ok, catalog_scope} <- TreeDx.Store.resolve_effective_scope(actor_id, repo_id) do
      {:ok, intersect_token_scope(catalog_scope, principal)}
    end
  end

  def require_capability(principal, capability, repo_id \\ nil, opts \\ []) do
    with {:ok, scope} <- effective_scope(principal, repo_id, opts) do
      if capability in (scope["capabilities"] || []) do
        {:ok, scope}
      else
        denied(capability: capability)
      end
    else
      {:error, %{"code" => "not_found"}} -> denied(capability: capability)
      {:error, %{code: "not_found"}} -> denied(capability: capability)
      other -> other
    end
  end

  def require_all(principal, capabilities, repo_id \\ nil, opts \\ []) do
    with {:ok, scope} <- effective_scope(principal, repo_id, opts) do
      missing = Enum.reject(capabilities, &(&1 in (scope["capabilities"] || [])))

      if missing == [] do
        {:ok, scope}
      else
        denied(capabilities: missing)
      end
    end
  end

  def require_any(principal, capabilities, repo_id \\ nil, opts \\ []) do
    with {:ok, scope} <- effective_scope(principal, repo_id, opts) do
      if Enum.any?(capabilities, &(&1 in (scope["capabilities"] || []))) do
        {:ok, scope}
      else
        denied(capabilities: capabilities)
      end
    end
  end

  def require_ref(scope, ref_name) do
    if allowed_ref?(scope, ref_name), do: :ok, else: denied(ref: ref_name)
  end

  def require_paths(scope, paths) do
    denied_paths = Enum.reject(paths, &allowed_path?(scope, &1))
    if denied_paths == [], do: :ok, else: denied(paths: denied_paths)
  end

  def reduce_scope(principal, requested_scope) do
    repo_ids = requested_scope["repoIds"] || requested_scope[:repo_ids] || []

    allowed =
      Enum.reduce(repo_ids, [], fn repo_id, acc ->
        case effective_scope(principal, repo_id) do
          {:ok, scope} -> [%{repoId: repo_id, scope: scope} | acc]
          _ -> acc
        end
      end)

    {:ok, Enum.reverse(allowed)}
  end

  def allowed_repo?(scope, repo_id),
    do: allowed?(scope["repoIds"] || scope["repo_ids"] || [], repo_id)

  def allowed_ref?(scope, ref), do: allowed?(scope["refs"] || [], ref)
  def allowed_path?(scope, path), do: allowed?(scope["paths"] || [], path)

  def put_grant(input) do
    input =
      input
      |> Map.put_new("id", "")
      |> Map.put_new("repoIds", ["*"])
      |> Map.put_new("refs", ["*"])
      |> Map.put_new("paths", ["**"])
      |> Map.put_new("capabilities", [])

    TreeDx.Store.put_capability_grant(input)
  end

  def list_grants(filters \\ %{}), do: TreeDx.Store.list_capability_grants(filters)

  defp intersect_token_scope(scope, %{"authMode" => "connected", "tokenScope" => token_scope})
       when is_map(token_scope) do
    scope
    |> maybe_intersect("repoIds", token_scope["repoIds"] || token_scope[:repoIds] || [])
    |> maybe_intersect(
      "capabilities",
      token_scope["capabilities"] || token_scope[:capabilities] || []
    )
    |> maybe_intersect("refs", token_scope["refs"] || token_scope[:refs] || [])
    |> maybe_intersect_paths(token_scope["paths"] || token_scope[:paths] || [])
  end

  defp intersect_token_scope(scope, _principal), do: scope

  defp maybe_intersect(scope, _key, []), do: scope

  defp maybe_intersect(scope, key, values) do
    existing = scope[key] || []
    Map.put(scope, key, Enum.filter(existing, &(&1 in values or "*" in values or "**" in values)))
  end

  defp maybe_intersect_paths(scope, []), do: scope

  defp maybe_intersect_paths(scope, token_paths) do
    existing = scope["paths"] || []

    paths =
      for existing_path <- existing,
          token_path <- token_paths,
          reduced <- intersect_path_pattern(existing_path, token_path),
          uniq: true,
          do: reduced

    Map.put(scope, "paths", paths)
  end

  defp intersect_path_pattern(existing, requested) do
    cond do
      existing in ["**", "*"] -> [requested]
      requested in ["**", "*"] -> [existing]
      match_pattern?(existing, requested) -> [requested]
      match_pattern?(requested, existing) -> [existing]
      true -> []
    end
  end

  defp denied(details) do
    capability =
      details[:capability] ||
        (details[:capabilities] && Enum.join(List.wrap(details[:capabilities]), ",")) ||
        "unknown"

    TreeDx.Observability.Metrics.incr("treedx_capability_denials_total", %{
      capability: capability
    })

    {:error,
     %{code: "permission_denied", message: "Permission denied.", details: Map.new(details)}}
  end

  defp allowed?(patterns, value), do: Enum.any?(patterns, &match_pattern?(&1, value))

  defp match_pattern?("**", _value), do: true
  defp match_pattern?("*", _value), do: true

  defp match_pattern?(pattern, value) do
    cond do
      String.ends_with?(pattern, "/*") ->
        prefix = String.trim_trailing(pattern, "*")
        String.starts_with?(value, prefix)

      String.ends_with?(pattern, "/**") ->
        prefix = String.trim_trailing(pattern, "**")
        directory = String.trim_trailing(prefix, "/")
        value == directory or String.starts_with?(value, prefix)

      String.ends_with?(pattern, "*") ->
        prefix = String.trim_trailing(pattern, "*")
        String.starts_with?(value, prefix)

      true ->
        pattern == value
    end
  end
end
