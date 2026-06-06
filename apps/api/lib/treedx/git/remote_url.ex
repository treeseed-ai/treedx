defmodule TreeDx.Git.RemoteUrl do
  @moduledoc false

  def reject_credential_url(url) do
    if credential_url?(url) do
      {:error, %{code: "validation_error", message: "remoteUrl must not contain credentials."}}
    else
      :ok
    end
  end

  def sanitize(nil), do: nil
  def sanitize("file://" <> _path), do: "file://redacted"

  def sanitize(url) when is_binary(url) do
    cond do
      String.starts_with?(url, "/") -> "local-path:redacted"
      true -> Regex.replace(~r{(https?://)[^/@\s]+@}i, url, "\\1")
    end
  end

  def credential_url?(url) when is_binary(url) do
    Regex.match?(~r{^(https?)://[^/\s]*@}i, url)
  end

  def credential_url?(_url), do: false

  def ssh?(url) when is_binary(url) do
    String.starts_with?(url, "ssh://") or
      (String.contains?(url, "@") and String.contains?(url, ":") and
         not String.starts_with?(url, "http") and not String.starts_with?(url, "file:"))
  end

  def ssh?(_url), do: false

  def http?(url) when is_binary(url),
    do: String.starts_with?(url, "http://") or String.starts_with?(url, "https://")

  def http?(_url), do: false
end
