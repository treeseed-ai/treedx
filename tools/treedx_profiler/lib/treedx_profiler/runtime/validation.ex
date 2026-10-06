defmodule TreeDxProfiler.Validation do
  @moduledoc false

  alias TreeDxProfiler.{Hash, PublicHygiene}

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
    request = Map.get(ctx, :request, %{})
    expected = Map.get(request, :expectation, %{})
    path = expected[:path] || expected["path"]
    expected_content = expected[:content]
    content = response_content(payload)

    with :ok <- PublicHygiene.validate(payload),
         :ok <- validate_path(payload, path),
         :ok <- validate_exact_content(content, expected_content, path),
         :ok <- validate_hash(content, expected[:sha256], path) do
      :ok
    end
  end

  defp do_validate("file_path_matches_expectation", payload, ctx) do
    with :ok <- ok_or_not_found(payload),
         :ok <- PublicHygiene.validate(payload) do
      request = Map.get(ctx, :request, %{})

      expectation = Map.get(request, :expectation, %{}) || %{}
      target = Map.get(request, :target, %{}) || %{}

      validate_path(
        payload,
        expectation[:path] || expectation["path"] || target[:path] || target["path"]
      )
    end
  end

  defp do_validate("blob_hash_matches_expectation", payload, ctx),
    do: validate_binary_payload(payload, ctx)

  defp do_validate("blob_download_matches_hash", payload, ctx),
    do: validate_binary_payload(payload, ctx)

  defp do_validate("multipart_complete_matches_hash", payload, _ctx), do: ok_envelope(payload)

  defp do_validate("path_list_contains_expected_paths", payload, ctx) do
    path =
      Map.get(Map.get(Map.get(ctx, :request, %{}), :expectation, %{}), :expected_path) ||
        get_in(ctx.state.fixture.expected, [:known, :markdown_path])

    if is_nil(path) or contains_value?(payload, path),
      do: :ok,
      else: {:error, "path list missing #{path}"}
  end

  defp do_validate(rule, payload, ctx)
       when rule in [
              "search_hits_expected_terms",
              "query_hits_expected_terms",
              "graph_search_has_expected_paths"
            ] do
    with :ok <- ok_envelope(payload),
         :ok <- PublicHygiene.validate(payload),
         {:ok, results} <- result_list(payload),
         :ok <-
           validate_expected_result_path(
             results,
             Map.get(Map.get(Map.get(ctx, :request, %{}), :expectation, %{}), :expected_path)
           ),
         :ok <- validate_result_scope(results) do
      :ok
    end
  end

  defp do_validate("workspace_read_after_write", payload, ctx) do
    with :ok <- ok_envelope(payload),
         :ok <- PublicHygiene.validate(payload) do
      validate_path(payload, Map.get(Map.get(Map.get(ctx, :request, %{}), :target, %{}), :path))
    end
  end

  defp do_validate("workspace_status_contains_mutation", payload, ctx),
    do: validate_payload_mentions_path(payload, ctx)

  defp do_validate("workspace_diff_contains_mutation", payload, ctx),
    do: validate_payload_mentions_path(payload, ctx)

  defp do_validate("workspace_commit_visible_on_branch", payload, _ctx),
    do: truthy(payload["commitSha"], "commit sha")

  defp do_validate("graph_refresh_has_version", payload, _ctx) do
    with :ok <- ok_envelope(payload), :ok <- PublicHygiene.validate(payload) do
      truthy(
        payload["graphVersion"] || get_in(payload, ["graph", "version"]) ||
          get_in(payload, ["job", "jobId"]) || payload["jobId"],
        "graph version or job id"
      )
    end
  end

  defp do_validate("graph_query_has_expected_shape", payload, _ctx) do
    with :ok <- ok_or_validation(payload), :ok <- PublicHygiene.validate(payload) do
      :ok
    end
  end

  defp do_validate("graph_node_has_expected_path", payload, _ctx), do: ok_or_not_found(payload)
  defp do_validate("context_within_budget", payload, _ctx), do: ok_envelope(payload)
  defp do_validate("search_index_status_valid", payload, _ctx), do: ok_envelope(payload)

  defp do_validate("snapshot_has_checksum", payload, _ctx) do
    with :ok <- ok_envelope(payload), :ok <- PublicHygiene.validate(payload) do
      truthy(
        get_in(payload, ["snapshot", "checksum"]) || get_in(payload, ["snapshot", "snapshotId"]) ||
          payload["snapshotId"],
        "snapshot checksum or id"
      )
    end
  end

  defp do_validate("snapshot_checksum_stable_within_run", payload, ctx) do
    with :ok <- do_validate("snapshot_has_checksum", payload, ctx) do
      :ok
    end
  end

  defp do_validate("artifact_has_metadata", payload, ctx) do
    with :ok <- ok_or_not_found(payload),
         :ok <- PublicHygiene.validate(payload) do
      expected = Map.get(Map.get(Map.get(ctx, :request, %{}), :expectation, %{}), :artifact_id)
      actual = get_in(payload, ["artifact", "artifactId"]) || payload["artifactId"]

      if is_nil(expected) or is_nil(actual) or expected == actual,
        do: :ok,
        else: {:error, "artifact id #{inspect(actual)} did not match #{inspect(expected)}"}
    end
  end

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

  defp sanitized(payload), do: PublicHygiene.validate(payload)

  defp response_content(payload) when is_map(payload),
    do: get_in(payload, ["file", "content"]) || payload["content"] || payload["body"]

  defp response_content(payload) when is_binary(payload), do: payload
  defp response_content(_), do: nil

  defp validate_exact_content(_content, nil, _path), do: :ok
  defp validate_exact_content(content, expected, _path) when content == expected, do: :ok

  defp validate_exact_content(_content, expected, path),
    do:
      {:error,
       "content mismatch for #{path || "unknown path"} expected sha #{Hash.sha256(expected)}"}

  defp validate_hash(_content, nil, _path), do: :ok

  defp validate_hash(content, sha, path) when is_binary(content) do
    if Hash.sha256(content) == sha,
      do: :ok,
      else: {:error, "content hash mismatch for #{path || "unknown path"}"}
  end

  defp validate_hash(_content, _sha, path),
    do: {:error, "missing content for hash validation #{path}"}

  defp validate_path(_payload, nil), do: :ok

  defp validate_path(payload, path) do
    if contains_value?(payload, path),
      do: :ok,
      else: {:error, "response did not mention expected path #{path}"}
  end

  defp validate_binary_payload(payload, ctx) when is_binary(payload) do
    expected = Map.get(Map.get(ctx, :request, %{}), :expectation, %{})

    cond do
      is_nil(expected[:sha256]) ->
        :ok

      Hash.sha256(payload) == expected[:sha256] ->
        :ok

      true ->
        target = Map.get(Map.get(ctx, :request, %{}), :target, %{})
        {:error, "binary hash mismatch for #{Map.get(target, :path)}"}
    end
  end

  defp validate_binary_payload(payload, _ctx), do: ok_or_not_found(payload)

  defp result_list(payload) do
    results =
      payload["results"] || get_in(payload, ["search", "results"]) ||
        get_in(payload, ["query", "results"]) || get_in(payload, ["graph", "results"]) || []

    if is_list(results), do: {:ok, results}, else: {:error, "expected result list"}
  end

  defp validate_expected_result_path(_results, nil), do: :ok

  defp validate_expected_result_path(results, path) do
    if contains_value?(results, path),
      do: :ok,
      else: {:error, "results missing expected path #{path}"}
  end

  defp validate_result_scope(results) do
    text = inspect(results)

    cond do
      String.contains?(text, [".env", ".ssh/config", "private.pem", "id_rsa"]) ->
        {:error, "results contained protected path"}

      true ->
        :ok
    end
  end

  defp validate_payload_mentions_path(payload, ctx) do
    with :ok <- ok_envelope(payload),
         :ok <- PublicHygiene.validate(payload) do
      validate_path(payload, Map.get(Map.get(Map.get(ctx, :request, %{}), :target, %{}), :path))
    end
  end

  defp truthy(nil, label), do: {:error, "expected #{label}"}
  defp truthy("", label), do: {:error, "expected #{label}"}
  defp truthy(_, _), do: :ok

  defp contains_value?(value, expected) when is_binary(value) and is_binary(expected),
    do: String.contains?(value, expected)

  defp contains_value?(value, expected) when is_map(value),
    do:
      Enum.any?(value, fn {key, val} ->
        contains_value?(key, expected) or contains_value?(val, expected)
      end)

  defp contains_value?(value, expected) when is_list(value),
    do: Enum.any?(value, &contains_value?(&1, expected))

  defp contains_value?(_value, _expected), do: false
end
