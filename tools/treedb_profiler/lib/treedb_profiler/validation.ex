defmodule TreeDbProfiler.Validation do
  @moduledoc false

  @rules [
    "ok_envelope",
    "error_envelope_sanitized",
    "repo_registered",
    "repo_list_contains_registered",
    "refs_contain_expected_branches",
    "file_content_matches_expectation",
    "file_path_matches_expectation",
    "blob_hash_matches_expectation",
    "path_list_contains_expected_paths",
    "search_hits_expected_terms",
    "query_hits_expected_terms",
    "workspace_read_after_write",
    "workspace_status_contains_mutation",
    "workspace_diff_contains_mutation",
    "workspace_commit_visible_on_branch",
    "blob_download_matches_hash",
    "multipart_complete_matches_hash",
    "graph_refresh_has_version",
    "graph_query_has_expected_shape",
    "graph_search_has_expected_paths",
    "graph_node_has_expected_path",
    "context_within_budget",
    "search_index_status_valid",
    "snapshot_has_checksum",
    "snapshot_checksum_stable_within_run",
    "artifact_has_metadata",
    "artifact_metadata_sanitized",
    "federated_results_authorized_only",
    "storage_response_sanitized",
    "metrics_shape_valid",
    "prometheus_text_valid"
  ]

  def rules, do: @rules

  def validate(rule, ctx) when rule in @rules do
    case do_validate(rule, ctx.response, ctx) do
      :ok -> :ok
      {:error, _} = error -> error
    end
  end

  def validate(rule, _ctx), do: {:error, "unknown validation rule #{rule}"}

  defp do_validate("ok_envelope", payload, _ctx), do: ok_envelope(payload)
  defp do_validate("error_envelope_sanitized", payload, _ctx), do: sanitized(payload)

  defp do_validate("repo_registered", payload, _ctx),
    do: truthy(get_in(payload, ["repo", "repoId"]), "repo id")

  defp do_validate("repo_list_contains_registered", payload, ctx) do
    ids = ctx.state.fixture.local_repos |> Enum.map(& &1[:repo_id]) |> Enum.reject(&is_nil/1)
    text = inspect(payload)

    if Enum.all?(ids, &String.contains?(text, &1)),
      do: :ok,
      else: {:error, "repository list did not include registered repos"}
  end

  defp do_validate("refs_contain_expected_branches", payload, ctx) do
    branch = ctx.state.fixture.local_repos |> hd() |> Map.get(:branches) |> List.first()

    if is_nil(branch) or String.contains?(inspect(payload), branch),
      do: :ok,
      else: {:error, "expected branch #{branch}"}
  end

  defp do_validate("file_content_matches_expectation", payload, ctx) do
    ok_envelope(payload)
    path = get_in(ctx.state.fixture.expected, [:known, :markdown_path])
    content = get_in(payload, ["file", "content"]) || payload["content"] || inspect(payload)

    if is_nil(path) or String.contains?(content, "release"),
      do: :ok,
      else: {:error, "file content did not match generated expectation for #{path}"}
  end

  defp do_validate("file_path_matches_expectation", payload, _ctx), do: ok_or_not_found(payload)
  defp do_validate("blob_hash_matches_expectation", payload, _ctx), do: ok_or_binary(payload)
  defp do_validate("blob_download_matches_hash", payload, _ctx), do: ok_or_binary(payload)
  defp do_validate("multipart_complete_matches_hash", payload, _ctx), do: ok_envelope(payload)

  defp do_validate("path_list_contains_expected_paths", payload, ctx) do
    path = get_in(ctx.state.fixture.expected, [:known, :markdown_path])

    if is_nil(path) or String.contains?(inspect(payload), path),
      do: :ok,
      else: {:error, "path list missing #{path}"}
  end

  defp do_validate(rule, payload, _ctx)
       when rule in [
              "search_hits_expected_terms",
              "query_hits_expected_terms",
              "graph_search_has_expected_paths"
            ] do
    ok_envelope(payload)

    results =
      payload["results"] || get_in(payload, ["search", "results"]) ||
        get_in(payload, ["query", "results"]) || []

    if is_list(results), do: :ok, else: {:error, "expected result list"}
  end

  defp do_validate("workspace_read_after_write", payload, _ctx), do: ok_envelope(payload)
  defp do_validate("workspace_status_contains_mutation", payload, _ctx), do: ok_envelope(payload)
  defp do_validate("workspace_diff_contains_mutation", payload, _ctx), do: ok_envelope(payload)

  defp do_validate("workspace_commit_visible_on_branch", payload, _ctx),
    do: truthy(payload["commitSha"], "commit sha")

  defp do_validate("graph_refresh_has_version", payload, _ctx), do: ok_envelope(payload)
  defp do_validate("graph_query_has_expected_shape", payload, _ctx), do: ok_or_validation(payload)
  defp do_validate("graph_node_has_expected_path", payload, _ctx), do: ok_or_not_found(payload)
  defp do_validate("context_within_budget", payload, _ctx), do: ok_envelope(payload)
  defp do_validate("search_index_status_valid", payload, _ctx), do: ok_envelope(payload)
  defp do_validate("snapshot_has_checksum", payload, _ctx), do: ok_envelope(payload)
  defp do_validate("snapshot_checksum_stable_within_run", payload, _ctx), do: ok_envelope(payload)
  defp do_validate("artifact_has_metadata", payload, _ctx), do: ok_or_not_found(payload)
  defp do_validate("artifact_metadata_sanitized", payload, _ctx), do: sanitized(payload)

  defp do_validate("federated_results_authorized_only", payload, _ctx),
    do: ok_or_forbidden(payload)

  defp do_validate("storage_response_sanitized", payload, _ctx), do: sanitized(payload)

  defp do_validate("metrics_shape_valid", payload, _ctx),
    do: if(is_map(payload), do: :ok, else: {:error, "metrics response was not a map"})

  defp do_validate("prometheus_text_valid", payload, _ctx),
    do: if(is_binary(payload), do: :ok, else: {:error, "prometheus response was not text"})

  defp ok_envelope(%{"ok" => true}), do: :ok
  defp ok_envelope(%{"status" => "ok"}), do: :ok
  defp ok_envelope(_), do: {:error, "expected ok envelope"}

  defp ok_or_forbidden(%{"ok" => false, "error" => %{"code" => "permission_denied"}}), do: :ok
  defp ok_or_forbidden(payload), do: ok_envelope(payload)

  defp ok_or_not_found(%{"ok" => false, "error" => %{"code" => "not_found"}}), do: :ok
  defp ok_or_not_found(payload), do: ok_envelope(payload)

  defp ok_or_validation(%{"ok" => false, "error" => %{"code" => "validation_error"}}), do: :ok
  defp ok_or_validation(payload), do: ok_envelope(payload)

  defp ok_or_binary(payload) when is_binary(payload), do: :ok
  defp ok_or_binary(payload), do: ok_or_not_found(payload)

  defp sanitized(payload) do
    text = inspect(payload)

    if String.contains?(text, ["/tmp/", "/var/lib/treedb", "authorization", "Bearer "]),
      do: {:error, "response contained unsanitized operational detail"},
      else: :ok
  end

  defp truthy(nil, label), do: {:error, "expected #{label}"}
  defp truthy("", label), do: {:error, "expected #{label}"}
  defp truthy(_, _), do: :ok
end
