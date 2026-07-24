defmodule TreeDxProfiler.FederationTopology do
  @moduledoc false

  def from_opts(opts) do
    [
      %{id: "node_a", url: opts.federation_node_a_url || opts.base_url},
      %{id: "node_b", url: opts.federation_node_b_url},
      %{id: "node_c", url: opts.federation_node_c_url}
    ]
    |> Enum.filter(&present?/1)
  end

  defp present?(%{url: url}), do: is_binary(url) and String.trim(url) != ""
end
