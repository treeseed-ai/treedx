defmodule TreeDbProfiler.OperationCatalog do
  @moduledoc false

  alias TreeDbProfiler.EndpointMatrix

  def all, do: EndpointMatrix.load()

  def by_type(type) do
    all()
    |> Enum.filter(&(&1["operationType"] == to_string(type)))
  end

  def by_category(category) do
    all()
    |> Enum.filter(&(&1["category"] == to_string(category)))
  end

  def randomizable do
    all()
    |> Enum.filter(& &1["randomizable"])
  end
end
