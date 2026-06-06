defmodule TreeDx.Files.Overlay do
  @moduledoc false

  def read_overlay(record) do
    with {:ok, %{"contentBase64" => content}} when is_binary(content) <-
           TreeDx.Store.read_workspace_file_content(record),
         {:ok, bytes} <- Base.decode64(content),
         {:ok, text} <- utf8(bytes) do
      {:ok, text}
    else
      {:ok, %{"contentBase64" => nil}} ->
        {:error, %{code: "not_found", message: "File not found."}}

      :error ->
        {:error, %{code: "unsupported_media_type", message: "File is not valid UTF-8."}}

      other ->
        other
    end
  end

  def utf8(bytes) do
    text = IO.iodata_to_binary(bytes)

    if String.valid?(text) do
      {:ok, text}
    else
      {:error, %{code: "unsupported_media_type", message: "File is not valid UTF-8."}}
    end
  end
end
