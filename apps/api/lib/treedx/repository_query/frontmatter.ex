defmodule TreeDx.RepositoryQuery.Frontmatter do
  @moduledoc false

  def parse(source) when is_binary(source) do
    normalized = String.trim_leading(source, "\uFEFF")

    cond do
      String.starts_with?(normalized, "---\r\n") ->
        parse_delimited(source, binary_part(normalized, 5, byte_size(normalized) - 5))

      String.starts_with?(normalized, "---\n") ->
        parse_delimited(source, binary_part(normalized, 4, byte_size(normalized) - 4))

      true ->
        %{frontmatter: %{}, body: source, frontmatterError: nil}
    end
  end

  defp parse_delimited(original, remainder) do
    case Regex.run(~r/(?:\A|\r?\n)---(?:\r?\n|\z)/, remainder, return: :index) do
      [{index, length}] ->
        yaml = binary_part(remainder, 0, index)
        body_start = index + length
        body = binary_part(remainder, body_start, byte_size(remainder) - body_start)

        case parse_yaml(yaml) do
          {:ok, frontmatter} ->
            %{frontmatter: frontmatter, body: body, frontmatterError: nil}

          {:error, error} ->
            %{
              frontmatter: %{},
              body: original,
              frontmatterError: %{code: "invalid_frontmatter", message: error}
            }
        end

      _ ->
        %{
          frontmatter: %{},
          body: original,
          frontmatterError: %{
            code: "invalid_frontmatter",
            message: "Frontmatter opening delimiter has no closing delimiter."
          }
        }
    end
  end

  defp parse_yaml(yaml) do
    case :yamerl_constr.string(String.to_charlist(yaml)) do
      [doc] ->
        case normalize_yaml(doc) do
          value when is_map(value) -> {:ok, value}
          _ -> {:error, "YAML frontmatter must contain a top-level mapping."}
        end

      [] ->
        {:ok, %{}}
    end
  rescue
    error -> {:error, Exception.message(error)}
  catch
    :exit, reason -> {:error, inspect(reason)}
    kind, reason -> {:error, "#{kind}: #{inspect(reason)}"}
  end

  # Yamerl represents both character data and YAML sequences as Erlang lists.
  # An empty YAML sequence must be handled before the printable-charlist test:
  # List.ascii_printable?([]) is true and would otherwise corrupt [] into "".
  defp normalize_yaml([]), do: []

  defp normalize_yaml(value) when is_list(value) do
    cond do
      List.ascii_printable?(value) ->
        to_string(value)

      Keyword.keyword?(value) or Enum.all?(value, &match?({_, _}, &1)) ->
        Map.new(value, fn {key, val} -> {to_string_key(key), normalize_yaml(val)} end)

      true ->
        Enum.map(value, &normalize_yaml/1)
    end
  end

  defp normalize_yaml(value) when is_map(value) do
    Map.new(value, fn {key, val} -> {to_string_key(key), normalize_yaml(val)} end)
  end

  defp normalize_yaml(value) when is_boolean(value), do: value
  defp normalize_yaml(nil), do: nil
  defp normalize_yaml(value) when is_binary(value), do: value
  defp normalize_yaml(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_yaml(value), do: value

  defp to_string_key(value) when is_binary(value), do: value
  defp to_string_key(value) when is_atom(value), do: Atom.to_string(value)
  defp to_string_key(value), do: to_string(value)
end
