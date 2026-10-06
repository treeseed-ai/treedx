defmodule TreeDx.Files.Patch do
  @moduledoc false

  def apply(content, patch, path) when is_binary(content) and is_binary(patch) do
    lines = split_patch(patch)

    with :ok <- validate_target(lines, path),
         {:ok, hunks} <- parse_hunks(lines),
         :ok <- validate_empty_change(content, hunks),
         {:ok, patched} <- apply_hunks(content_lines(content), hunks, 0, []) do
      if valid_endings?(patched),
        do: {:ok, IO.iodata_to_binary(patched)},
        else: validation("a missing newline marker may only terminate the file.")
    end
  end

  def apply(_content, _patch, _path), do: validation("patch must be a string.")

  defp split_patch(patch) do
    lines = String.split(patch, "\n", trim: false)
    if String.ends_with?(patch, "\n"), do: Enum.drop(lines, -1), else: lines
  end

  defp content_lines(""), do: []

  defp content_lines(content) do
    parts = String.split(content, "\n", trim: false)
    {complete, [last]} = Enum.split(parts, length(parts) - 1)
    Enum.map(complete, &(&1 <> "\n")) ++ if(last == "", do: [], else: [last])
  end

  defp valid_endings?([]), do: true

  defp valid_endings?(lines),
    do: lines |> Enum.drop(-1) |> Enum.all?(&String.ends_with?(&1, "\n"))

  defp validate_empty_change(content, []) when content != "",
    do: validation("a hunkless change requires an empty file.")

  defp validate_empty_change(_, _), do: :ok

  defp validate_target(lines, path) do
    targets =
      lines
      |> Enum.take_while(&(not String.starts_with?(&1, "@@ ")))
      |> Enum.filter(&(String.starts_with?(&1, "--- ") or String.starts_with?(&1, "+++ ")))
      |> Enum.map(fn line ->
        line
        |> String.replace_prefix("--- ", "")
        |> String.replace_prefix("+++ ", "")
        |> String.split("\t", parts: 2)
        |> hd()
        |> String.replace_prefix("a/", "")
        |> String.replace_prefix("b/", "")
      end)
      |> Enum.reject(&(&1 == "/dev/null"))

    if targets == [] or Enum.all?(targets, &(&1 == path)),
      do: :ok,
      else: validation("patch target does not match path.")
  end

  defp parse_hunks(lines) do
    case Enum.drop_while(lines, &(not String.starts_with?(&1, "@@ "))) do
      [] ->
        if Enum.any?(lines, &(&1 in ["new file mode 100644", "deleted file mode 100644"])),
          do: {:ok, []},
          else: validation("patch must contain a hunk.")

      hunks ->
        parse_hunks(hunks, [])
    end
  end

  defp parse_hunks([], acc), do: {:ok, Enum.reverse(acc)}

  defp parse_hunks([header | rest], acc) do
    case Regex.named_captures(
           ~r/^@@ -(?<old_start>\d+)(?:,(?<old_count>\d+))? \+(?<new_start>\d+)(?:,(?<new_count>\d+))? @@(?:.*)$/,
           header
         ) do
      %{
        "old_start" => old_start,
        "old_count" => old_count,
        "new_start" => new_start,
        "new_count" => new_count
      } ->
        {body, tail} = Enum.split_while(rest, &(not String.starts_with?(&1, "@@ ")))

        hunk = %{
          old_start: String.to_integer(old_start),
          old_count: count(old_count),
          new_start: String.to_integer(new_start),
          new_count: count(new_count)
        }

        with {:ok, operations} <- parse_body(body, []),
             :ok <- validate_counts(hunk, operations) do
          parse_hunks(tail, [Map.put(hunk, :operations, operations) | acc])
        end

      _ ->
        validation("malformed patch hunk header.")
    end
  end

  defp count(""), do: 1
  defp count(value), do: String.to_integer(value)

  defp parse_body([], acc), do: {:ok, Enum.reverse(acc)}

  defp parse_body(["\\ No newline at end of file" | rest], [{kind, line} | acc]) do
    if String.ends_with?(line, "\n"),
      do: parse_body(rest, [{kind, binary_part(line, 0, byte_size(line) - 1)} | acc]),
      else: validation("duplicate missing newline marker.")
  end

  defp parse_body([<<kind, text::binary>> | rest], acc) when kind in [32, 43, 45],
    do: parse_body(rest, [{kind, text <> "\n"} | acc])

  defp parse_body(_, _), do: validation("malformed patch hunk.")

  defp validate_counts(hunk, operations) do
    old_count = Enum.count(operations, fn {kind, _} -> kind != 43 end)
    new_count = Enum.count(operations, fn {kind, _} -> kind != 45 end)

    if old_count == hunk.old_count and new_count == hunk.new_count and
         (old_count == 0 or hunk.old_start > 0) and (new_count == 0 or hunk.new_start > 0),
       do: :ok,
       else: validation("patch hunk counts do not match its body.")
  end

  defp apply_hunks(original, [], _cursor, acc), do: {:ok, Enum.reverse(acc) ++ original}

  defp apply_hunks(original, [hunk | rest], cursor, acc) do
    old_index = hunk.old_start - if(hunk.old_count == 0, do: 0, else: 1)
    new_index = hunk.new_start - if(hunk.new_count == 0, do: 0, else: 1)
    unchanged_count = old_index - cursor

    if unchanged_count < 0 or length(original) < unchanged_count or
         length(acc) + unchanged_count != new_index do
      conflict("patch hunk does not apply at its declared position.")
    else
      {unchanged, remaining} = Enum.split(original, unchanged_count)

      with {:ok, remaining, additions} <- apply_body(remaining, hunk.operations, []) do
        apply_hunks(
          remaining,
          rest,
          old_index + hunk.old_count,
          additions ++ Enum.reverse(unchanged) ++ acc
        )
      end
    end
  end

  defp apply_body(original, [], additions), do: {:ok, original, additions}

  defp apply_body(original, [{43, added} | rest], additions),
    do: apply_body(original, rest, [added | additions])

  defp apply_body([expected | original], [{32, expected} | rest], additions),
    do: apply_body(original, rest, [expected | additions])

  defp apply_body([expected | original], [{45, expected} | rest], additions),
    do: apply_body(original, rest, additions)

  defp apply_body(_, _, _), do: conflict("patch context does not match exact file bytes.")

  defp validation(message), do: {:error, %{code: "validation_error", message: message}}
  defp conflict(message), do: {:error, %{code: "conflict", message: message}}
end
