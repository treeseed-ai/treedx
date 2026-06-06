defmodule TreeDx.Files.Patch do
  @moduledoc false

  def apply(content, patch, path) when is_binary(content) and is_binary(patch) do
    lines = String.split(patch, "\n")

    with :ok <- validate_target(lines, path),
         {:ok, hunks} <- parse_hunks(lines),
         {:ok, patched} <- apply_hunks(String.split(content, "\n"), hunks) do
      {:ok, Enum.join(patched, "\n")}
    end
  end

  def apply(_content, _patch, _path),
    do: {:error, %{code: "validation_error", message: "patch must be a string."}}

  defp validate_target(lines, path) do
    targets =
      lines
      |> Enum.filter(&(String.starts_with?(&1, "--- ") or String.starts_with?(&1, "+++ ")))
      |> Enum.map(fn line ->
        line
        |> String.replace_prefix("--- ", "")
        |> String.replace_prefix("+++ ", "")
        |> String.trim()
        |> String.replace_prefix("a/", "")
        |> String.replace_prefix("b/", "")
      end)
      |> Enum.reject(&(&1 == "/dev/null"))

    if targets == [] or Enum.all?(targets, &(&1 == path)) do
      :ok
    else
      {:error, %{code: "validation_error", message: "patch target does not match path."}}
    end
  end

  defp parse_hunks(lines) do
    hunks =
      lines
      |> Enum.drop_while(&(not String.starts_with?(&1, "@@ ")))
      |> do_parse_hunks([])

    if hunks == [] do
      {:error, %{code: "validation_error", message: "patch must contain a hunk."}}
    else
      {:ok, Enum.reverse(hunks)}
    end
  end

  defp do_parse_hunks([], acc), do: acc

  defp do_parse_hunks([header | rest], acc) do
    case Regex.run(~r/^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@/, header) do
      [_, old_start, _new_start] ->
        {body, tail} = Enum.split_while(rest, &(not String.starts_with?(&1, "@@ ")))
        do_parse_hunks(tail, [%{old_start: String.to_integer(old_start), body: body} | acc])

      _ ->
        acc
    end
  end

  defp apply_hunks(original, hunks), do: apply_hunks(original, hunks, 1, [])

  defp apply_hunks(original, [], _line_no, acc), do: {:ok, Enum.reverse(acc) ++ original}

  defp apply_hunks(original, [%{old_start: old_start, body: body} | rest], line_no, acc) do
    unchanged_count = old_start - line_no

    if unchanged_count < 0 or length(original) < unchanged_count do
      {:error, %{code: "conflict", message: "patch hunk does not apply."}}
    else
      {unchanged, original} = Enum.split(original, unchanged_count)

      case apply_hunk_body(original, body, []) do
        {:ok, remaining, additions, consumed} ->
          apply_hunks(
            remaining,
            rest,
            old_start + consumed,
            Enum.reverse(additions) ++ unchanged ++ acc
          )

        error ->
          error
      end
    end
  end

  defp apply_hunk_body(original, [], additions), do: {:ok, original, additions, 0}

  defp apply_hunk_body(original, [line | rest], additions) do
    case line do
      " " <> expected -> consume_expected(original, expected, rest, [expected | additions], 1)
      "-" <> expected -> consume_expected(original, expected, rest, additions, 1)
      "+" <> added -> add_line(original, rest, [added | additions])
      "" -> apply_hunk_body(original, rest, ["" | additions])
      _ -> {:error, %{code: "validation_error", message: "malformed patch hunk."}}
    end
  end

  defp consume_expected([expected | original], expected, rest, additions, consumed_delta) do
    case apply_hunk_body(original, rest, additions) do
      {:ok, remaining, additions, consumed} ->
        {:ok, remaining, additions, consumed + consumed_delta}

      error ->
        error
    end
  end

  defp consume_expected(_original, _expected, _rest, _additions, _delta),
    do: {:error, %{code: "conflict", message: "patch context does not match."}}

  defp add_line(original, rest, additions) do
    case apply_hunk_body(original, rest, additions) do
      {:ok, remaining, additions, consumed} -> {:ok, remaining, additions, consumed}
      error -> error
    end
  end
end
