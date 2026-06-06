defmodule TreeDbSdk do
  @moduledoc false

  defdelegate health(client), to: TreeDbSdk.Client
  defdelegate version(client), to: TreeDbSdk.Client
  defdelegate whoami(client), to: TreeDbSdk.Client
  defdelegate effective_scope(client), to: TreeDbSdk.Client
  defdelegate auth_mode(client), to: TreeDbSdk.Client
  defdelegate create_dev_token(client), to: TreeDbSdk.Client
end
