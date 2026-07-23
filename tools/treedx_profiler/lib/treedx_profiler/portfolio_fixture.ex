defmodule TreeDxProfiler.PortfolioFixture do
  @moduledoc false

  alias TreeDxProfiler.DataGenerator

  def build(opts, repo_index) do
    defn = TreeDxProfiler.Fixtures.definition("small-docs", opts.size)
    name = DataGenerator.repo_name(opts.portfolio_repo_prefix, opts.profile_id, repo_index)

    %{
      family: "portfolio",
      size: opts.size,
      name: name,
      markdown: max(div(defn.markdown, 2), 4),
      text: max(div(defn.text, 2), 1),
      json: max(div(defn.json, 2), 1),
      binary: max(div(defn.binary, 2), 0),
      blob_sizes: defn.blob_sizes,
      branches: max(defn.branches, 1),
      commits: max(defn.commits, 2),
      tags: 1,
      links_per_doc: max(defn.links_per_doc, 1),
      sections_per_doc: max(defn.sections_per_doc, 2),
      search_terms: defn.search_terms,
      protected_paths: defn.protected_paths,
      workspace_writes: max(defn.workspace_writes, 2),
      workspace_patches: max(defn.workspace_patches, 1),
      workspace_deletes: max(defn.workspace_deletes, 1),
      repo_index: repo_index
    }
  end
end
