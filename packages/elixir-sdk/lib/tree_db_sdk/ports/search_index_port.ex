defmodule TreeDbSdk.Ports.SearchIndexPort do
  @moduledoc false
  @callback request(TreeDbSdk.Client.t(), atom(), String.t(), term(), map()) ::
              {:ok, term()} | {:error, TreeDbSdk.Error.t()}
end
