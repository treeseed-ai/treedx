defmodule TreeDxSdk.Ports.AuditPort do
  @moduledoc false
  @callback request(TreeDxSdk.Client.t(), atom(), String.t(), term(), map()) ::
              {:ok, term()} | {:error, TreeDxSdk.Error.t()}
end
