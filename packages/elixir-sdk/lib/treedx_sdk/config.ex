defmodule TreeDxSdk.Config do
  @moduledoc false
  defstruct [:base_url, :token, :auth_provider, :transport, :timeout, default_headers: %{}]
end
