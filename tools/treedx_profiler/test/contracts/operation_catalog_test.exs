defmodule TreeDxProfiler.OperationCatalogTest do
  use ExUnit.Case, async: true

  alias TreeDxProfiler.OperationCatalog

  test "exposes operations by type and category" do
    assert OperationCatalog.all() != []
    assert Enum.all?(OperationCatalog.randomizable(), &is_boolean(&1["randomizable"]))
    assert Enum.any?(OperationCatalog.by_type(:read), &(&1["method"] == "GET"))
    assert Enum.any?(OperationCatalog.by_category(:workspace), &("workspace" in &1["tags"]))
  end
end
