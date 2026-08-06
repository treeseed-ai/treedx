defmodule TreeDxWeb.RequestBodyReader do
  @moduledoc false

  @max_compressed_bytes 2 * 1_048_576
  @max_expanded_bytes 8 * 1_048_576

  def read_body(conn, opts) do
    if Plug.Conn.get_req_header(conn, "content-encoding") == ["gzip"] do
      with {:ok, compressed, conn} <- read_all(conn, opts, [], 0),
           {:ok, expanded} <- gunzip(compressed),
           :ok <- require_expanded_limit(expanded) do
        {:ok, expanded, conn}
      end
    else
      Plug.Conn.read_body(conn, opts)
    end
  end

  defp read_all(conn, opts, chunks, size) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, chunk, conn} -> bounded_chunk(chunk, conn, chunks, size, false, opts)
      {:more, chunk, conn} -> bounded_chunk(chunk, conn, chunks, size, true, opts)
      other -> other
    end
  end

  defp bounded_chunk(chunk, conn, chunks, size, more, opts) do
    next_size = size + byte_size(chunk)

    cond do
      next_size > @max_compressed_bytes -> {:error, :too_large}
      more -> read_all(conn, opts, [chunk | chunks], next_size)
      true -> {:ok, chunks |> Enum.reverse([chunk]) |> IO.iodata_to_binary(), conn}
    end
  end

  defp gunzip(value) do
    try do
      {:ok, :zlib.gunzip(value)}
    rescue
      ErlangError -> {:error, :invalid_gzip}
    end
  end

  defp require_expanded_limit(value) when byte_size(value) <= @max_expanded_bytes, do: :ok
  defp require_expanded_limit(_value), do: {:error, :too_large}
end
