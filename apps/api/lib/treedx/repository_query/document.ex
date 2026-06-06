defmodule TreeDx.RepositoryQuery.Document do
  @moduledoc false

  alias TreeDx.RepositoryQuery.Frontmatter

  def from_entry(repo, ref, entry, opts \\ []) do
    encoding = Keyword.get(opts, :encoding, "utf8")
    parse_frontmatter = Keyword.get(opts, :parse_frontmatter, true)

    with {:ok, blob} <-
           TreeDx.Git.read_blob(TreeDx.RepositoryStorage.path!(repo), ref, entry["path"]),
         {:ok, bytes} <- Base.decode64(blob["contentBase64"]) do
      build(entry, blob, bytes, encoding, parse_frontmatter)
    else
      :error -> {:error, %{code: "internal_error", message: "Invalid blob encoding."}}
      other -> other
    end
  end

  def from_path(repo, ref, path, opts \\ []) do
    with {:ok, blob} <- TreeDx.Git.read_blob(TreeDx.RepositoryStorage.path!(repo), ref, path),
         {:ok, bytes} <- Base.decode64(blob["contentBase64"]) do
      entry = %{
        "path" => path,
        "objectId" => blob["objectId"],
        "kind" => "blob",
        "size" => blob["byteLength"]
      }

      build(
        entry,
        blob,
        bytes,
        Keyword.get(opts, :encoding, "utf8"),
        Keyword.get(opts, :parse_frontmatter, true)
      )
    else
      :error ->
        {:error, %{code: "internal_error", message: "Invalid blob encoding."}}

      {:error, %{"code" => "not_found"}} ->
        {:error, %{code: "not_found", message: "File not found."}}

      other ->
        other
    end
  end

  defp build(entry, blob, _bytes, "base64", _parse_frontmatter) do
    {:ok,
     base(entry, blob)
     |> Map.merge(%{
       "encoding" => "base64",
       "content" => blob["contentBase64"],
       "frontmatter" => %{},
       "body" => nil,
       "frontmatterError" => nil
     })}
  end

  defp build(entry, blob, bytes, "utf8", parse_frontmatter) do
    if String.valid?(bytes) do
      content = IO.iodata_to_binary(bytes)

      parsed =
        if parse_frontmatter and markdown?(entry["path"]) do
          Frontmatter.parse(content)
        else
          %{frontmatter: %{}, body: content, frontmatterError: nil}
        end

      {:ok,
       base(entry, blob)
       |> Map.merge(%{
         "encoding" => "utf8",
         "content" => content,
         "frontmatter" => parsed.frontmatter,
         "body" => parsed.body,
         "frontmatterError" => parsed.frontmatterError
       })}
    else
      {:error, %{code: "unsupported_media_type", message: "File is not valid UTF-8."}}
    end
  end

  defp build(_entry, _blob, _bytes, _encoding, _parse_frontmatter),
    do: {:error, %{code: "validation_error", message: "encoding must be utf8 or base64."}}

  defp base(entry, blob) do
    path = entry["path"] || blob["path"]

    %{
      "path" => path,
      "name" => Path.basename(path),
      "extension" => path |> Path.extname(),
      "objectId" => blob["objectId"],
      "size" => blob["byteLength"]
    }
  end

  defp markdown?(path), do: Path.extname(path) in [".md", ".mdx", ".markdown"]
end
