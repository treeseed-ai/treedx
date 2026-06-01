defmodule TreeDb.Ids do
  @moduledoc false

  def token do
    "treedb_dev_" <> Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
  end

  def workspace do
    "ws_" <> Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
  end

  def hash_token(token) do
    "blake3:" <> Base.encode16(:crypto.hash(:blake2s, token), case: :lower)
  end
end
