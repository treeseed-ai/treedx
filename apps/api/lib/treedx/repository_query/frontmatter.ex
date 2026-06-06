defmodule TreeDx.RepositoryQuery.Frontmatter do
  @moduledoc false

  def parse(source) when is_binary(source) do
    if String.starts_with?(source, "---\n") do
      parse_delimited(source)
    else
      %{frontmatter: %{}, body: source, frontmatterError: nil}
    end
  end

  defp parse_delimited(source) do
    case :binary.match(source, "\n---\n", scope: {4, byte_size(source) - 4}) do
      {index, 5} ->
        yaml = binary_part(source, 4, index - 4)
        body_start = index + 5
        body = binary_part(source, body_start, byte_size(source) - body_start)

        case parse_yaml(yaml) do
          {:ok, frontmatter} ->
            %{frontmatter: frontmatter, body: body, frontmatterError: nil}

          {:error, error} ->
            %{
              frontmatter: %{},
              body: source,
              frontmatterError: %{code: "invalid_frontmatter", message: error}
            }
        end

      _ ->
        %{frontmatter: %{}, body: source, frontmatterError: nil}
    end
  end

  defp parse_yaml(yaml) do
    case :yamerl_constr.string(String.to_charlist(yaml)) do
      [doc] when is_list(doc) ->
        {:ok, normalize_yaml(doc)}

      [doc] when is_map(doc) ->
        {:ok, normalize_yaml(doc)}

      [_] ->
        {:ok, %{}}

      [] ->
        {:ok, %{}}
    end
  rescue
    error -> {:error, Exception.message(error)}
  catch
    :exit, reason -> {:error, inspect(reason)}
    kind, reason -> {:error, "#{kind}: #{inspect(reason)}"}
  end

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

  defp normalize_yaml(value) when is_binary(value), do: value
  defp normalize_yaml(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_yaml(value), do: value

  defp to_string_key(value) when is_binary(value), do: value
  defp to_string_key(value) when is_atom(value), do: Atom.to_string(value)
  defp to_string_key(value), do: to_string(value)
end
