defmodule TreeDxProfiler.GitFixture do
  @moduledoc false

  def create_repo!(root, repo_def, seed) do
    repo_name = repo_def.name
    path = Path.join(root, repo_name)
    File.rm_rf!(path)
    File.mkdir_p!(path)

    run!(["init", "-b", "main"], path)
    run!(["config", "user.name", "TreeDX Profiler"], path)
    run!(["config", "user.email", "profiler@example.invalid"], path)

    files = write_files!(path, repo_def, seed)
    run!(["add", "."], path)
    run!(["commit", "-m", "Initial profiler fixture"], path)

    write_history!(path, repo_def, seed)

    branches = write_branches!(path, repo_def)
    tags = write_tags!(path, repo_def)
    run!(["checkout", "main"], path)

    %{
      family: repo_def.family,
      size: repo_def.size,
      name: repo_name,
      path: path,
      files: files,
      branches: branches,
      tags: tags,
      commits: repo_def.commits,
      workspace: workspace_targets(repo_def),
      default_ref: "refs/heads/main"
    }
  end

  defp write_files!(path, repo_def, seed) do
    markdown = write_markdown!(path, repo_def, seed)
    text = write_text!(path, repo_def, seed)
    json = write_json!(path, repo_def, seed)
    binary = write_binary!(path, repo_def, seed)
    protected = write_protected!(path, repo_def)
    workspace = write_workspace_targets!(path, repo_def, seed)

    markdown ++ text ++ json ++ binary ++ protected ++ workspace
  end

  defp write_markdown!(path, repo_def, seed) do
    for index <- 1..repo_def.markdown do
      topic = topic(index)
      file = "docs/#{topic}/doc-#{pad(index)}.md"
      links = links(index, repo_def.markdown, repo_def.links_per_doc)
      sections = sections(index, repo_def.sections_per_doc)
      entities = entities(index)

      content = """
      ---
      title: Profiler Doc #{index}
      fixture: #{repo_def.family}
      size: #{repo_def.size}
      seed: #{seed}
      entity: #{hd(entities)}
      ---
      # Profiler Doc #{index}

      release provenance migration fixture #{index} profile_term_#{pad(index)}

      #{Enum.join(sections, "\n\n")}

      Entities: #{Enum.join(entities, ", ")}

      #{Enum.map_join(links, "\n", &"- [Related](#{&1})")}
      """

      write!(path, file, content)

      %{
        path: file,
        kind: "markdown",
        content: content,
        sha256: sha256(content),
        byte_length: byte_size(content),
        content_type: "text/markdown",
        links: links,
        sections: length(sections),
        entities: entities
      }
    end
  end

  defp write_text!(path, repo_def, seed) do
    for index <- 1..repo_def.text do
      file = "plain/#{group(index)}/text-#{pad(index)}.txt"

      content =
        "release provenance plain fixture #{repo_def.family} #{index} profile_term_#{pad(index)} seed #{seed}\n"

      write!(path, file, content)

      %{
        path: file,
        kind: "text",
        content: content,
        sha256: sha256(content),
        byte_length: byte_size(content),
        content_type: "text/plain"
      }
    end
  end

  defp write_json!(path, repo_def, seed) do
    for index <- 1..repo_def.json do
      file = "data/#{group(index)}/item-#{pad(index)}.json"

      content =
        Jason.encode!(
          %{
            id: index,
            fixture: repo_def.family,
            size: repo_def.size,
            term: "release",
            profileTerm: "profile_term_#{pad(index)}",
            provenance: "deterministic",
            entity: "EntityAlpha#{index}",
            seed: seed
          },
          pretty: true
        ) <> "\n"

      write!(path, file, content)

      %{
        path: file,
        kind: "json",
        content: content,
        sha256: sha256(content),
        byte_length: byte_size(content),
        content_type: "application/json"
      }
    end
  end

  defp write_binary!(path, repo_def, seed) do
    if repo_def.binary <= 0 do
      []
    else
      do_write_binary!(path, repo_def, seed)
    end
  end

  defp do_write_binary!(path, repo_def, seed) do
    sizes = repo_def.blob_sizes || [1024]

    content_types = [
      {"application/octet-stream", "blob"},
      {"image/png", "image"},
      {"application/x-tar", "archive"}
    ]

    for index <- 1..repo_def.binary do
      size = Enum.at(sizes, rem(index - 1, length(sizes)))
      {content_type, prefix} = Enum.at(content_types, rem(index - 1, length(content_types)))
      extension = if prefix == "image", do: "png", else: "bin"
      file = "assets/#{prefix}/#{prefix}-#{pad(index)}.#{extension}"
      content = binary_content("#{seed}:#{repo_def.family}:#{repo_def.size}", index, size)
      write!(path, file, content)

      %{
        path: file,
        kind: "binary",
        sha256: sha256(content),
        byte_length: byte_size(content),
        content_type: content_type
      }
    end
  end

  defp write_protected!(path, repo_def) do
    for protected_path <- repo_def.protected_paths do
      content = "protected fixture path #{protected_path}\n"
      write!(path, protected_path, content)

      %{
        path: protected_path,
        kind: "protected",
        content: content,
        sha256: sha256(content),
        byte_length: byte_size(content),
        content_type: "text/plain"
      }
    end
  end

  defp write_workspace_targets!(path, repo_def, seed) do
    writes =
      for index <- 1..max(repo_def.workspace_writes, 1) do
        file = "workspace/write-#{pad(index)}.md"
        content = "# Workspace Write #{index}\n\nrelease workspace write #{seed}\n"
        write!(path, file, content)

        %{
          path: file,
          kind: "workspace_write",
          content: content,
          sha256: sha256(content),
          byte_length: byte_size(content),
          content_type: "text/markdown"
        }
      end

    patches =
      for index <- 1..max(repo_def.workspace_patches, 1) do
        file = "workspace/patch-#{pad(index)}.md"
        content = "# Workspace Patch #{index}\n\nrelease workspace patch base #{seed}\n"
        write!(path, file, content)

        %{
          path: file,
          kind: "workspace_patch",
          content: content,
          sha256: sha256(content),
          byte_length: byte_size(content),
          content_type: "text/markdown"
        }
      end

    deletes =
      for index <- 1..max(repo_def.workspace_deletes, 1) do
        file = "workspace/delete-#{pad(index)}.md"
        content = "# Workspace Delete #{index}\n\nrelease workspace delete base #{seed}\n"
        write!(path, file, content)

        %{
          path: file,
          kind: "workspace_delete",
          content: content,
          sha256: sha256(content),
          byte_length: byte_size(content),
          content_type: "text/markdown"
        }
      end

    writes ++ patches ++ deletes
  end

  defp write_history!(path, repo_def, seed) do
    for index <- 2..max(repo_def.commits, 2) do
      file = "history/commit-#{pad(index)}.md"
      write!(path, file, "# History #{index}\n\nrelease provenance history #{seed} #{index}\n")
      run!(["add", "."], path)
      run!(["commit", "-m", "Profiler history #{index}"], path)
    end
  end

  defp write_branches!(path, repo_def) do
    for index <- 1..repo_def.branches do
      branch = "fixture/branch-#{pad(index)}"
      run!(["checkout", "-B", branch], path)
      branch_file = "docs/branch/branch-#{pad(index)}.md"
      write!(path, branch_file, "# Branch #{index}\n\nrelease provenance branch #{index}\n")
      run!(["add", "."], path)
      run!(["commit", "-m", "Add #{branch}"], path)
      run!(["checkout", "main"], path)
      "refs/heads/#{branch}"
    end
  end

  defp write_tags!(path, repo_def) do
    for index <- 1..max(repo_def.tags, 1) do
      tag = "fixture-v#{pad(index)}"
      run!(["tag", "-f", tag], path)
      "refs/tags/#{tag}"
    end
  end

  defp workspace_targets(repo_def) do
    %{
      writes:
        for(index <- 1..max(repo_def.workspace_writes, 1), do: "workspace/write-#{pad(index)}.md"),
      patches:
        for(
          index <- 1..max(repo_def.workspace_patches, 1),
          do: "workspace/patch-#{pad(index)}.md"
        ),
      deletes:
        for(
          index <- 1..max(repo_def.workspace_deletes, 1),
          do: "workspace/delete-#{pad(index)}.md"
        ),
      blobs: for(index <- 1..max(repo_def.binary, 1), do: "workspace/blob-#{pad(index)}.bin")
    }
  end

  defp write!(root, relative, content) do
    path = Path.join(root, relative)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
  end

  defp run!(args, cwd) do
    case System.cmd("git", args, cd: cwd, stderr_to_stdout: true) do
      {_out, 0} -> :ok
      {out, status} -> raise "git #{Enum.join(args, " ")} failed with #{status}: #{out}"
    end
  end

  defp links(index, count, links_per_doc) do
    for offset <- 1..max(links_per_doc, 1) do
      target = rem(index + offset - 1, max(count, 1)) + 1
      "../#{topic(target)}/doc-#{pad(target)}.md"
    end
  end

  defp sections(index, sections_per_doc) do
    for section <- 1..max(sections_per_doc, 1) do
      "## Section #{section}\n\nrelease section #{section} for document #{index}"
    end
  end

  defp entities(index),
    do: [
      "EntityAlpha#{index}",
      "EntityBeta#{index}",
      "System#{rem(index, 7)}",
      "Release#{rem(index, 11)}"
    ]

  defp topic(index),
    do: "topic-#{Integer.to_string(rem(index - 1, 10) + 1) |> String.pad_leading(2, "0")}"

  defp group(index),
    do: "group-#{Integer.to_string(rem(index - 1, 10) + 1) |> String.pad_leading(2, "0")}"

  defp pad(value), do: value |> Integer.to_string() |> String.pad_leading(6, "0")
  defp sha256(content), do: :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)

  defp binary_content(seed, index, bytes) do
    stream =
      Stream.unfold(0, fn n ->
        chunk = :crypto.hash(:sha256, "#{seed}:#{index}:#{n}")
        {chunk, n + 1}
      end)

    stream
    |> Enum.take(div(bytes, 32) + 1)
    |> IO.iodata_to_binary()
    |> binary_part(0, bytes)
  end
end
