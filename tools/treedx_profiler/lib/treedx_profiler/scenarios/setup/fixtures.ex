defmodule TreeDxProfiler.Fixtures do
  @moduledoc false

  alias TreeDxProfiler.GitFixture

  @canonical [
    "small-docs",
    "medium-mixed",
    "binary-assets",
    "large-history",
    "graph-rich",
    "workspace-heavy"
  ]

  @sizes ["small", "medium", "large", "xl"]

  def canonical, do: @canonical
  def sizes, do: @sizes

  def definition(fixture_id, size \\ "small") do
    fixture_id
    |> definition_file!()
    |> File.read!()
    |> Jason.decode!()
    |> expand_definition(size)
  end

  def generate!("all", opts) do
    fixtures =
      Enum.map(@canonical, fn fixture_id ->
        generate_one!(fixture_id, opts)
      end)

    merge_fixtures("all", opts, fixtures)
  end

  def generate!(fixture_id, opts), do: generate_one!(fixture_id, opts)

  defp generate_one!(fixture_id, opts) when fixture_id in @canonical do
    size = Keyword.get(opts, :size, "small")
    defn = definition(fixture_id, size)
    profile_id = opts[:profile_id]
    repo_prefix = opts[:repo_prefix] || "profile-"
    seed = opts[:seed] || "#{fixture_id}-#{size}-#{profile_id}"
    root = Path.join([opts[:fixture_root], profile_id, fixture_id])
    File.mkdir_p!(root)

    repos =
      for index <- 1..defn.repos do
        GitFixture.create_repo!(root, repo_def(defn, index, repo_prefix), seed)
      end

    expected = TreeDxProfiler.Expectations.from_fixture(defn, repos)

    %{
      fixture_id: fixture_id,
      size: size,
      seed: seed,
      repo_prefix: repo_prefix,
      root: root,
      local_repos: repos,
      expected: expected,
      definition: defn,
      families: [%{fixture_id: fixture_id, size: size, definition: defn, repos: repos}]
    }
  end

  defp generate_one!(fixture_id, _opts), do: raise("unknown fixture #{inspect(fixture_id)}")

  defp merge_fixtures(fixture_id, opts, fixtures) do
    local_repos = Enum.flat_map(fixtures, & &1.local_repos)

    defn = %{
      id: fixture_id,
      size: Keyword.get(opts, :size, "small"),
      search_terms: fixtures |> Enum.flat_map(& &1.definition.search_terms) |> Enum.uniq(),
      repos: length(local_repos),
      markdown: Enum.sum(Enum.map(fixtures, & &1.definition.markdown)),
      text: Enum.sum(Enum.map(fixtures, & &1.definition.text)),
      json: Enum.sum(Enum.map(fixtures, & &1.definition.json)),
      binary: Enum.sum(Enum.map(fixtures, & &1.definition.binary)),
      branches: Enum.max(Enum.map(fixtures, & &1.definition.branches)),
      commits: Enum.max(Enum.map(fixtures, & &1.definition.commits)),
      links_per_doc: Enum.max(Enum.map(fixtures, & &1.definition.links_per_doc)),
      sections_per_doc: Enum.max(Enum.map(fixtures, & &1.definition.sections_per_doc)),
      workspace_writes: Enum.sum(Enum.map(fixtures, & &1.definition.workspace_writes)),
      workspace_patches: Enum.sum(Enum.map(fixtures, & &1.definition.workspace_patches)),
      workspace_deletes: Enum.sum(Enum.map(fixtures, & &1.definition.workspace_deletes)),
      protected_paths: default_protected_paths(),
      blob_sizes: fixtures |> Enum.flat_map(& &1.definition.blob_sizes) |> Enum.uniq()
    }

    %{
      fixture_id: fixture_id,
      size: Keyword.get(opts, :size, "small"),
      repo_prefix: opts[:repo_prefix] || "profile-",
      seed:
        opts[:seed] || "#{fixture_id}-#{Keyword.get(opts, :size, "small")}-#{opts[:profile_id]}",
      root: Path.join(opts[:fixture_root], opts[:profile_id]),
      local_repos: local_repos,
      expected: TreeDxProfiler.Expectations.from_fixture(defn, local_repos),
      definition: defn,
      families: Enum.flat_map(fixtures, & &1.families)
    }
  end

  defp expand_definition(raw, size) when size in @sizes do
    scale = get_in(raw, ["scale", size]) || raise("fixture #{raw["id"]} has no #{size} scale")

    %{
      id: raw["id"],
      description: raw["description"],
      size: size,
      repos: scale["repos"],
      markdown: scale["markdown"],
      text: scale["text"],
      json: scale["json"],
      binary: scale["binary"],
      branches: scale["branches"],
      commits: scale["commits"],
      links_per_doc: scale["linksPerDoc"],
      sections_per_doc: scale["sectionsPerDoc"],
      workspace_writes: scale["workspaceWrites"],
      workspace_patches: scale["workspacePatches"],
      workspace_deletes: scale["workspaceDeletes"],
      blob_sizes: scale["blobSizes"] || get_in(raw, ["blobs", "sizes"]) || [1024],
      search_terms: raw["searchTerms"] || ["release"],
      content: raw["content"] || %{},
      history: raw["history"] || %{},
      protected_paths: default_protected_paths()
    }
  end

  defp expand_definition(raw, size), do: raise("fixture #{raw["id"]} has no #{size} scale")

  defp repo_def(defn, index, repo_prefix) do
    %{
      family: defn.id,
      size: defn.size,
      name: "#{repo_prefix}#{defn.id}-#{defn.size}-#{index}",
      markdown: defn.markdown,
      text: defn.text,
      json: defn.json,
      binary: defn.binary,
      blob_sizes: defn.blob_sizes,
      branches: defn.branches,
      commits: defn.commits,
      tags: get_in(defn, [:history, "tags"]) || get_in(defn, [:history, :tags]) || 1,
      links_per_doc: defn.links_per_doc,
      sections_per_doc: defn.sections_per_doc,
      search_terms: defn.search_terms,
      protected_paths: defn.protected_paths,
      workspace_writes: defn.workspace_writes,
      workspace_patches: defn.workspace_patches,
      workspace_deletes: defn.workspace_deletes,
      repo_index: index
    }
  end

  defp definition_file!(fixture_id) when fixture_id in @canonical do
    case System.get_env("TREEDX_PROFILER_ROOT") do
      nil -> Path.expand("../../fixtures/#{fixture_id}.yaml", __DIR__)
      root -> Path.expand("fixtures/#{fixture_id}.yaml", root)
    end
  end

  defp definition_file!(fixture_id), do: raise("unknown fixture #{inspect(fixture_id)}")

  defp default_protected_paths,
    do: [".env", ".env.local", ".ssh/config", "private.pem", "id_rsa", ".gitignore"]
end
