defmodule TreeDx.Auth.Jwt do
  @moduledoc false

  def validate_config, do: TreeDx.Auth.Verifiers.Hs256Dev.validate_config()
  def verify(token), do: TreeDx.Auth.Verifiers.Hs256Dev.verify(token)
  def verifier_info, do: TreeDx.Auth.Verifiers.Hs256Dev.info()
end
