defmodule TreeDxProfiler.SemanticExpectation do
  @moduledoc false

  alias TreeDxProfiler.Hash

  def file_from_repo(repo, path) when is_map(repo) and is_binary(path) do
    (repo[:readable_paths] || repo.readable_paths || [])
    |> Enum.find(&(&1.path == path || &1[:path] == path))
  end

  def binary_from_repo(repo, path) when is_map(repo) and is_binary(path) do
    (repo[:binary_paths] || repo.binary_paths || [])
    |> Enum.find(&(&1.path == path || &1[:path] == path))
  end

  def file_from_workspace(workspace, path) when is_map(workspace) and is_binary(path) do
    workspace
    |> Map.get(:written_files, %{})
    |> case do
      files when is_map(files) -> Map.get(files, path)
      files when is_list(files) -> Enum.find(files, &(&1.path == path || &1[:path] == path))
      _ -> nil
    end
  end

  def content_expectation(content, extra \\ %{}) when is_binary(content) do
    Map.merge(
      %{
        content: content,
        sha256: Hash.sha256(content),
        byte_length: byte_size(content),
        search_terms: unique_terms(content)
      },
      extra
    )
  end

  def unique_terms(content) when is_binary(content) do
    Regex.scan(
      ~r/(profile[_-]term[_-]\d+|EntityAlpha\d+|Generated Portfolio Document \d+)/,
      content
    )
    |> Enum.map(&List.first/1)
    |> Enum.uniq()
    |> case do
      [] -> ["release"]
      terms -> terms
    end
  end

  def expected_search_path(state, repo_id) do
    repo =
      state
      |> Map.get(:fixture, %{})
      |> Map.get(:local_repos, [])
      |> Enum.find(&(&1[:repo_id] == repo_id || &1.repo_id == repo_id))

    file = repo && Enum.find(repo.files || [], &(&1[:kind] in ["markdown", "text", "json"]))

    if file do
      %{path: file.path, content: file[:content], term: preferred_term(file[:content])}
    end
  end

  def preferred_term(content) when is_binary(content) do
    unique_terms(content) |> List.first()
  end

  def preferred_term(_), do: "release"
end
