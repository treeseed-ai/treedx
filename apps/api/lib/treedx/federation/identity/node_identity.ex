defmodule TreeDx.Federation.NodeIdentity do
  @moduledoc false

  @private_prefix "treedx-ecdsa-p256-private:"
  @public_prefix "treedx-ecdsa-p256-public:"

  def node_id,
    do:
      System.get_env("TREEDX_FEDERATION_NODE_ID") || System.get_env("TREEDX_NODE_ID") ||
        "node_local"

  def base_url do
    System.get_env("TREEDX_FEDERATION_NODE_BASE_URL") ||
      "http://#{System.get_env("PHX_HOST") || "localhost"}:#{System.get_env("PORT") || "4000"}"
  end

  def ensure_keys! do
    private_path = private_key_path()
    public_path = public_key_path()

    if !File.exists?(private_path) or legacy_key?(private_path) do
      File.mkdir_p!(Path.dirname(private_path))
      File.mkdir_p!(Path.dirname(public_path))
      {public_key, private_key} = :crypto.generate_key(:ecdh, :prime256v1)
      File.write!(private_path, @private_prefix <> Base.encode64(private_key))
      File.write!(public_path, @public_prefix <> Base.encode64(public_key))
    end

    unless File.exists?(public_path) do
      raise "missing TreeDX federation public key at #{public_path}"
    end

    :ok
  end

  def public_key_pem do
    ensure_keys!()
    File.read!(public_key_path())
  end

  def sign(payload) when is_map(payload) do
    payload
    |> canonical_json()
    |> sign_binary()
  end

  def sign_binary(data) when is_binary(data) do
    ensure_keys!()

    :crypto.sign(:ecdsa, :sha256, data, [private_key(), :prime256v1])
    |> Base.url_encode64(padding: false)
  end

  def verify(payload, signature, public_key_pem) when is_map(payload) and is_binary(signature) do
    verify_binary(canonical_json(payload), signature, public_key_pem)
  end

  def verify_binary(data, signature, public_key_pem)
      when is_binary(data) and is_binary(signature) and is_binary(public_key_pem) do
    with {:ok, public_key} <- parse_public_key(public_key_pem),
         {:ok, decoded_signature} <- Base.url_decode64(signature, padding: false) do
      :crypto.verify(:ecdsa, :sha256, data, decoded_signature, [public_key, :prime256v1])
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  def signed(payload) when is_map(payload) do
    Map.put(payload, "signature", sign(payload))
  end

  def canonical_json(payload), do: Jason.encode!(payload)

  defp private_key do
    private_key_path()
    |> File.read!()
    |> String.trim()
    |> String.replace_prefix(@private_prefix, "")
    |> Base.decode64!()
  end

  defp parse_public_key(public_key_pem) do
    public_key_pem
    |> String.trim()
    |> String.replace_prefix(@public_prefix, "")
    |> Base.decode64()
  end

  defp legacy_key?(path) do
    not String.starts_with?(File.read!(path) |> String.trim(), @private_prefix)
  end

  defp private_key_path do
    System.get_env("TREEDX_FEDERATION_NODE_PRIVATE_KEY_PATH") ||
      Path.join([TreeDx.Store.data_dir(), "keys", "node-private.pem"])
  end

  defp public_key_path do
    System.get_env("TREEDX_FEDERATION_NODE_PUBLIC_KEY_PATH") ||
      Path.join([TreeDx.Store.data_dir(), "keys", "node-public.pem"])
  end
end
