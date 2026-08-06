defmodule TreeDx.Files.ChangesetPatch do
  @moduledoc false

  @max_files 500

  def parse(patch) when is_binary(patch) do
    with {:ok, sections} <- split_sections(String.split(patch, "\n", trim: false)),
         :ok <- validate_count(sections) do
      sections
      |> Enum.reduce_while({:ok, []}, fn section, {:ok, acc} ->
        case parse_section(section) do
          {:ok, change} -> {:cont, {:ok, [change | acc]}}
          error -> {:halt, error}
        end
      end)
      |> then(fn
        {:ok, changes} -> validate_unique(Enum.reverse(changes))
        error -> error
      end)
    end
  end

  def parse(_), do: error("patch must be a UTF-8 string.")

  defp split_sections(lines) do
    {sections, current, prelude} =
      Enum.reduce(lines, {[], [], []}, fn line, {sections, current, prelude} ->
        cond do
          String.starts_with?(line, "diff --git ") and current != [] ->
            {[Enum.reverse(current) | sections], [line], prelude}

          String.starts_with?(line, "diff --git ") ->
            {sections, [line], prelude}

          current == [] ->
            {sections, current, [line | prelude]}

          true ->
            {sections, [line | current], prelude}
        end
      end)

    sections = if current == [], do: sections, else: [Enum.reverse(current) | sections]

    if Enum.all?(prelude, &(String.trim(&1) == "")) and sections != [] do
      {:ok, Enum.reverse(sections)}
    else
      error("patch must contain canonical diff --git sections only.")
    end
  end

  defp parse_section(lines) do
    diff_header = List.first(lines)
    old_header = Enum.find(lines, &String.starts_with?(&1, "--- "))
    new_header = Enum.find(lines, &String.starts_with?(&1, "+++ "))

    with {:ok, {diff_old, diff_new}} <- parse_diff_header(diff_header),
         {:ok, old_path} <- parse_target(old_header, "--- ", "a/"),
         {:ok, new_path} <- parse_target(new_header, "+++ ", "b/"),
         {:ok, op, path} <- classify(old_path, new_path),
         :ok <- require_matching_headers(diff_old, diff_new, path),
         true <- Enum.any?(lines, &String.starts_with?(&1, "@@ ")) do
      {:ok, %{op: op, path: path, patch: Enum.join(lines, "\n")}}
    else
      false -> error("every changeset file must contain at least one hunk.")
      other -> other
    end
  end

  defp parse_diff_header("diff --git a/" <> value) do
    case String.split(value, " b/", parts: 2) do
      [old_path, new_path] when old_path != "" and new_path != "" -> {:ok, {old_path, new_path}}
      _ -> error("diff --git headers must contain matching a/ and b/ paths.")
    end
  end

  defp parse_diff_header(_),
    do: error("every changeset file must begin with a canonical diff --git header.")

  defp require_matching_headers(path, path, path), do: :ok

  defp require_matching_headers(_old_path, _new_path, _path),
    do: error("diff --git and file headers must identify the same path.")

  defp parse_target(nil, _prefix, _side), do: error("file headers are required.")

  defp parse_target(line, prefix, side) do
    target = line |> String.replace_prefix(prefix, "") |> String.split("\t", parts: 2) |> hd()

    cond do
      target == "/dev/null" -> {:ok, nil}
      String.starts_with?(target, side) -> {:ok, String.replace_prefix(target, side, "")}
      true -> error("file headers must use a/ and b/ paths or /dev/null.")
    end
  end

  defp classify(nil, nil), do: error("a file cannot be absent before and after a change.")
  defp classify(nil, path), do: {:ok, :create, path}
  defp classify(path, nil), do: {:ok, :delete, path}
  defp classify(path, path), do: {:ok, :modify, path}

  defp classify(_old_path, _new_path),
    do: error("renames must be normalized to a delete and a create.")

  defp validate_count(sections) when length(sections) <= @max_files, do: :ok
  defp validate_count(_), do: error("a changeset may modify at most 500 files.")

  defp validate_unique(changes) do
    paths = Enum.map(changes, & &1.path)

    if length(paths) == MapSet.size(MapSet.new(paths)) do
      {:ok, changes}
    else
      error("a changeset may contain each path only once.")
    end
  end

  defp error(message), do: {:error, %{code: "validation_error", message: message}}
end
