defmodule TreeDxSdk do
  @moduledoc false

  defdelegate health(client), to: TreeDxSdk.Client
  defdelegate version(client), to: TreeDxSdk.Client
  defdelegate whoami(client), to: TreeDxSdk.Client
  defdelegate effective_scope(client), to: TreeDxSdk.Client
  defdelegate auth_mode(client), to: TreeDxSdk.Client
  defdelegate create_dev_token(client), to: TreeDxSdk.Client
end
