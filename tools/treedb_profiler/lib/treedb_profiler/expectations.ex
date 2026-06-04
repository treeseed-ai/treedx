defmodule TreeDbProfiler.Expectations do
  @moduledoc false

  def from_fixture(defn, repos) do
    all_files = Enum.flat_map(repos, & &1.files)
    visible_files = Enum.reject(all_files, &(&1.kind == "protected"))
    readable_files = Enum.filter(visible_files, &(&1.kind in ["markdown", "text", "json"]))
    binary_files = Enum.filter(visible_files, &(&1.kind == "binary"))
    markdown_files = Enum.filter(visible_files, &(&1.kind == "markdown"))

    %{
      repo_count: length(repos),
      repos: Enum.map(repos, &repo_expectation/1),
      file_counts: %{
        markdown: Enum.count(all_files, &(&1.kind == "markdown")),
        text: Enum.count(all_files, &(&1.kind == "text")),
        json: Enum.count(all_files, &(&1.kind == "json")),
        binary: Enum.count(all_files, &(&1.kind == "binary")),
        protected: Enum.count(all_files, &(&1.kind == "protected"))
      },
      path_expectations: %{
        readable_paths: Enum.map(readable_files, & &1.path),
        protected_paths: defn.protected_paths,
        nested_path_prefixes: nested_prefixes(visible_files)
      },
      content_hashes:
        all_files
        |> Enum.reject(&(&1.kind == "protected"))
        |> Map.new(fn file ->
          {file.path,
           %{
             sha256: file.sha256,
             byte_length: file.byte_length,
             content_type: file.content_type
           }}
        end),
      search_hits:
        Map.new(
          defn.search_terms,
          fn term ->
            hits = Enum.count(visible_files, &searchable?(&1, term))
            {term, %{min_hits: min(hits, 1), exact_generated_hits: hits}}
          end
        ),
      graph: %{
        min_nodes: max(length(readable_files), 1),
        min_edges: Enum.sum(Enum.map(markdown_files, &length(&1[:links] || []))),
        expected_sections: Enum.sum(Enum.map(markdown_files, &(&1[:sections] || 0))),
        expected_entities: Enum.sum(Enum.map(markdown_files, &length(&1[:entities] || []))),
        known_paths: Enum.map(Enum.take(markdown_files, 20), & &1.path),
        known_links: markdown_files |> Enum.flat_map(&(&1[:links] || [])) |> Enum.take(50)
      },
      workspace: workspace_expectations(repos),
      snapshot: %{
        expected_paths: Enum.map(Enum.take(markdown_files, 50), & &1.path),
        checksum_inputs: Enum.map(Enum.take(markdown_files, 50), & &1.sha256)
      },
      known: %{
        markdown_path: first_path(markdown_files),
        text_path: visible_files |> Enum.filter(&(&1.kind == "text")) |> first_path(),
        json_path: visible_files |> Enum.filter(&(&1.kind == "json")) |> first_path(),
        binary_path: first_path(binary_files),
        search_term: hd(defn.search_terms),
        context_query: hd(defn.search_terms)
      }
    }
  end

  defp repo_expectation(repo) do
    %{
      name: repo.name,
      default_ref: repo.default_ref,
      branches: repo.branches || [],
      tags: repo.tags || [],
      files:
        Enum.map(repo.files, &Map.take(&1, [:path, :kind, :sha256, :byte_length, :content_type])),
      commits: repo.commits
    }
  end

  defp workspace_expectations(repos) do
    primary = hd(repos)

    %{
      write_targets: primary.workspace.writes,
      patch_targets: primary.workspace.patches,
      delete_targets: primary.workspace.deletes,
      blob_targets: primary.workspace.blobs
    }
  end

  defp nested_prefixes(files) do
    files
    |> Enum.map(&Path.dirname(&1.path))
    |> Enum.reject(&(&1 == "."))
    |> Enum.uniq()
    |> Enum.take(50)
  end

  defp first_path([]), do: nil
  defp first_path([file | _]), do: file.path

  defp searchable?(%{content: content}, term) when is_binary(content),
    do: String.contains?(String.downcase(content), String.downcase(term))

  defp searchable?(_, _), do: false
end
