defmodule TreeDxSdk.Test.MockTransport do
  def start_link do
    Agent.start_link(fn -> [] end)
  end

  def client(pid) do
    TreeDxSdk.Client.new(base_url: "http://localhost:4000", transport: {__MODULE__, pid})
  end

  def requests(pid), do: Agent.get(pid, &Enum.reverse/1)

  def request(pid, _config, request) do
    Agent.update(pid, &[request | &1])
    {:ok, %TreeDxSdk.Transport.Response{status: 200, headers: %{}, data: %{"ok" => true}}}
  end
end
