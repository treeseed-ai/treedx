defmodule TreeDxWeb.RouteOpenApiInventoryTest do
  use ExUnit.Case, async: true

  alias TreeDxWeb.OpenApiContractAssertions

  test "router and OpenAPI route inventory stay synchronized" do
    openapi = OpenApiContractAssertions.openapi()

    router_routes =
      TreeDxWeb.Router.__routes__()
      |> Enum.filter(&(&1.plug != Phoenix.LiveDashboard.Router))
      |> Enum.map(fn route ->
        {String.downcase(to_string(route.verb)), normalize_path(route.path)}
      end)
      |> MapSet.new()

    openapi_routes =
      openapi["paths"]
      |> Enum.flat_map(fn {path, methods} ->
        methods
        |> Map.keys()
        |> Enum.map(&{&1, path})
      end)
      |> MapSet.new()

    assert MapSet.difference(router_routes, openapi_routes) == MapSet.new()
    assert MapSet.difference(openapi_routes, router_routes) == MapSet.new()

    for {method, path} <- MapSet.to_list(openapi_routes) do
      operation = get_in(openapi, ["paths", path, method])
      assert is_binary(operation["operationId"])
      assert is_binary(operation["summary"])
      assert Map.has_key?(operation, "x-treedx-required-capabilities")
    end
  end

  defp normalize_path(path) do
    path
    |> String.replace(~r/:([A-Za-z0-9_]+)/, "{\\1}")
  end
end
