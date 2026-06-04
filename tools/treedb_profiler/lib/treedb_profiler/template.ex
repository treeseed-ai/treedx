defmodule TreeDbProfiler.Template do
  @moduledoc false

  def render_path(path, state) do
    render(path, variables(state))
  end

  def render_body(template, state) when is_map(template),
    do: render_value(template, variables(state))

  def render_body(nil, _state), do: nil

  def variables(state) do
    expectation = state.fixture.expected
    repo = hd(state.fixture.local_repos)
    secondary = Enum.at(state.fixture.local_repos, 1)

    %{
      "repo_id" => repo[:repo_id],
      "secondary_repo_id" => secondary && secondary[:repo_id],
      "workspace_id" => state[:workspace_id],
      "primary_ref" => state[:branch_name] || "refs/heads/main",
      "branch_ref" => hd(repo.branches || ["refs/heads/main"]),
      "known_markdown_path" => get_in(expectation, [:known, :markdown_path]),
      "known_text_path" => get_in(expectation, [:known, :text_path]),
      "known_json_path" => get_in(expectation, [:known, :json_path]),
      "known_binary_path" => get_in(expectation, [:known, :binary_path]),
      "workspace_write_path" => expectation.workspace.write_targets |> List.first(),
      "workspace_patch_path" => expectation.workspace.patch_targets |> List.first(),
      "workspace_delete_path" => expectation.workspace.delete_targets |> List.first(),
      "snapshot_id" => state[:snapshot_id],
      "artifact_id" => state[:artifact_id],
      "upload_id" => state[:upload_id],
      "search_term" => get_in(expectation, [:known, :search_term]) || "release",
      "context_query" => get_in(expectation, [:known, :context_query]) || "release"
    }
  end

  defp render(value, vars) do
    try do
      Regex.replace(~r/\{([A-Za-z0-9_]+)\}/, value, fn _, key ->
        case Map.get(vars, key) do
          nil -> throw({:missing_template_variable, key})
          replacement -> to_string(replacement)
        end
      end)
    catch
      {:missing_template_variable, key} -> {:unavailable, "missing #{key}"}
    end
  end

  defp render_value(value, vars) when is_binary(value), do: render(value, vars)
  defp render_value(value, vars) when is_list(value), do: Enum.map(value, &render_value(&1, vars))

  defp render_value(value, vars) when is_map(value) do
    value
    |> Enum.map(fn {k, v} -> {k, render_value(v, vars)} end)
    |> Map.new()
  end

  defp render_value(value, _vars), do: value
end
