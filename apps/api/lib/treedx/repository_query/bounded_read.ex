defmodule TreeDx.RepositoryQuery.BoundedRead do
  @moduledoc false

  @max_read_bytes 196_608

  def normalize(paths, params) do
    max_bytes = params["maxBytes"]
    offset = params["offsetBytes"] || 0

    cond do
      is_nil(max_bytes) and offset == 0 ->
        {:ok, nil}

      !is_integer(max_bytes) or max_bytes < 1 or max_bytes > @max_read_bytes ->
        {:error, validation("maxBytes must be an integer between 1 and #{@max_read_bytes}.")}

      !is_integer(offset) or offset < 0 ->
        {:error, validation("offsetBytes must be a non-negative integer.")}

      length(paths) != 1 ->
        {:error, validation("Bounded reads require exactly one path.")}

      true ->
        {:ok, %{max_bytes: max_bytes, offset: offset}}
    end
  end

  def project(document, nil), do: {:ok, document}

  def project(document, %{max_bytes: max_bytes, offset: offset}) do
    content = document["content"] || ""
    total = byte_size(content)

    cond do
      offset > total ->
        {:error, validation("offsetBytes exceeds the encoded content size.")}

      !utf8_boundary?(content, offset) ->
        {:error, validation("offsetBytes must identify a UTF-8 boundary.")}

      true ->
        chunk = safe_chunk(content, offset, min(max_bytes, total - offset))
        next_offset = offset + byte_size(chunk)

        {:ok,
         Map.merge(document, %{
           "content" => chunk,
           "body" => nil,
           "frontmatter" => %{},
           "frontmatterError" => nil,
           "contentBytes" => total,
           "returnedBytes" => byte_size(chunk),
           "offsetBytes" => offset,
           "nextOffsetBytes" => if(next_offset < total, do: next_offset, else: nil),
           "truncated" => next_offset < total
         })}
    end
  end

  defp utf8_boundary?(content, offset),
    do: String.valid?(binary_part(content, offset, byte_size(content) - offset))

  defp safe_chunk(_content, _offset, 0), do: ""

  defp safe_chunk(content, offset, length) do
    chunk = binary_part(content, offset, length)
    if String.valid?(chunk), do: chunk, else: safe_chunk(content, offset, length - 1)
  end

  defp validation(message), do: %{code: "validation_error", message: message}
end
