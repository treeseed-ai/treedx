defmodule TreeDb.SdkGraphMappingTest do
  use ExUnit.Case, async: true

  test "TreeDB graph shapes map to SDK-compatible graph and context contracts" do
    node = %{
      "id" => "file:abc",
      "nodeType" => "File",
      "path" => "docs/readme.md",
      "title" => "Read Me",
      "data" => %{"frontmatter" => %{"title" => "Read Me"}}
    }

    edge = %{
      "id" => "edge:abc",
      "type" => "LINKS_TO",
      "sourceId" => "file:abc",
      "targetId" => "file:def",
      "data" => %{}
    }

    query_result = %{
      "seedIds" => ["file:abc"],
      "nodes" => [%{"node" => node, "score" => 9.0, "depth" => 0, "reasons" => ["query"]}],
      "edges" => [edge],
      "providerId" => "treedb-graph-mvp"
    }

    context = %{
      "seedIds" => ["file:abc"],
      "includedNodeIds" => ["file:abc"],
      "includedPaths" => ["docs/readme.md"],
      "nodes" => [%{"node" => node, "text" => "context", "tokenEstimate" => 2}],
      "edges" => [edge]
    }

    assert node["nodeType"] in ["File", "Section", "Tag", "Series", "Reference", "Entity"]
    assert edge["type"] in ["LINKS_TO", "REFERENCES", "HAS_TAG", "DEFINED_BY", "DEFINES"]
    assert query_result["providerId"] == "treedb-graph-mvp"
    assert context["includedPaths"] == ["docs/readme.md"]
    refute inspect(query_result) =~ "Objective"
    refute inspect(context) =~ "TreeSeed"
  end
end
