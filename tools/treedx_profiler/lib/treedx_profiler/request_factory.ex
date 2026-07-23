defmodule TreeDxProfiler.RequestFactory do
  @moduledoc false

  alias TreeDxProfiler.{Hash, ProfileRequest, SemanticExpectation}

  def request(operation_id, type, method, path, category, body, opts) do
    effect = Keyword.get(opts, :effect)

    ProfileRequest.new(%{
      id: "req_#{System.unique_integer([:positive])}",
      operation_id: operation_id,
      operation_type: type,
      method: method,
      path_template: template(path),
      path: path,
      category: category,
      body: body,
      headers: Keyword.get(opts, :headers, []),
      expected_status: List.wrap(Keyword.get(opts, :expected, 200)),
      validation_rule: validation_rule(operation_id),
      target: Keyword.get(opts, :target, %{}),
      expectation: Keyword.get(opts, :expectation, %{}),
      postconditions: Keyword.get(opts, :postconditions, []),
      race_context: Keyword.get(opts, :race, %{}),
      validation_probes: Keyword.get(opts, :probes, []),
      state_effect_on_status:
        Keyword.get(opts, :effect_on_status, if(effect, do: %{200 => effect}, else: %{})),
      state_effect: effect,
      failure_effect: Keyword.get(opts, :failure_effect),
      seed: Keyword.fetch!(opts, :seed)
    })
  end

  def semantic_content(content, path) do
    content
    |> SemanticExpectation.content_expectation(%{path: path, byte_length: byte_size(content)})
    |> Map.put(:sha256, Hash.sha256(content))
  end

  def patch_content(content, counter) do
    case String.split(content || "", "\n", parts: 2) do
      [first, rest] -> first <> " patched-#{counter}\n" <> rest
      [first] -> first <> " patched-#{counter}"
      [] -> "patched-#{counter}"
    end
  end

  def replace_first_line_patch(path, old_content, new_content) do
    old_first = old_content |> to_string() |> String.split("\n", parts: 2) |> List.first()
    new_first = new_content |> to_string() |> String.split("\n", parts: 2) |> List.first()

    ["--- a/#{path}", "+++ b/#{path}", "@@ -1,1 +1,1 @@", "-#{old_first}", "+#{new_first}"]
    |> Enum.join("\n")
  end

  def expected_search(repo) do
    case Enum.find(repo.readable_paths, &is_binary(Map.get(&1, :content))) do
      nil ->
        %{term: "release"}

      file ->
        %{
          term: SemanticExpectation.preferred_term(file.content),
          expected_path: file.path,
          content: file.content,
          sha256: file.sha256
        }
    end
  end

  def source_relative_path(path, opts) do
    data_dir = System.get_env("TREEDX_DATA_DIR") || Map.get(opts, :data_dir) || "/var/lib/treedx"
    path |> Path.expand() |> Path.relative_to(Path.expand(data_dir))
  end

  def workspace_status(workspace, opts) do
    request(
      "getWorkspaceStatus",
      :read,
      :get,
      "/api/v1/workspaces/#{workspace.workspace_id}/status",
      "workspace",
      nil,
      expected: [200, 404, 409],
      seed: opts.profile_id
    )
  end

  def unsupported_delete(opts) do
    request(
      "deleteRepository",
      :delete,
      :delete,
      "/api/v1/repos/not-supported",
      "repository",
      nil,
      expected: [404, 405],
      seed: opts.profile_id,
      effect: nil
    )
  end

  defp validation_rule(operation_id) do
    get_in(TreeDxProfiler.EndpointMatrix.operation_map(), [operation_id, "validation", "rule"]) ||
      "ok_envelope"
  end

  defp template(path) do
    path
    |> String.replace(~r/repo_[A-Za-z0-9_-]+/, "{repo_id}")
    |> String.replace(~r/ws_[A-Za-z0-9_-]+/, "{workspace_id}")
    |> String.replace(~r/snap_[A-Za-z0-9_-]+/, "{snapshot_id}")
    |> String.replace(~r/artifact_[A-Za-z0-9_-]+/, "{artifact_id}")
    |> String.replace(~r/\?.*$/, "")
  end
end
