defmodule TreeDx.Graph.PathSeedsTest do
  use ExUnit.Case, async: true

  alias TreeDx.Graph.PathSeeds
  alias TreeDx.RepositoryQuery.{ContentPaths, PathMatch}

  defp index(paths), do: %{"nodes" => Enum.map(paths, &%{"path" => &1})}
  defp available(paths), do: Map.new(paths, &{&1, true})

  test "extensionless globs match basenames, including question marks and zero directories" do
    paths = available(["docs/setup1.md", "docs/nested/setup2.yaml", "docs/setup12.md"])

    assert {:ok, ["docs/nested/setup2.yaml", "docs/setup1.md"]} =
             ContentPaths.select(["docs/**/setup?"], paths)

    assert {:ok, ["docs/setup1.md", "docs/setup12.md"]} =
             ContentPaths.select(["docs/**/*.md"], paths)

    assert {:ok, ["docs/nested/setup2.yaml", "docs/setup1.md", "docs/setup12.md"]} =
             ContentPaths.select(["docs/**/setup*"], paths)

    refute PathMatch.matches?("docs/setup?", "docs/setup1.md")
    assert ContentPaths.matches?("docs/setup?", "docs/setup1.md")
    refute ContentPaths.matches?("docs/*.yaml", "docs/setup1.md")
  end

  test "exact names win, unique names resolve, and ambiguous single names fail" do
    paths = available(["docs/setup.md", "docs/setup.yaml", "docs/guide.mdx"])
    assert {:ok, ["docs/guide.mdx"]} = ContentPaths.select(["docs/guide"], paths)
    assert {:error, %{code: "conflict"}} = ContentPaths.select(["docs/setup"], paths)
    assert {:ok, ["docs/setup.md"]} = ContentPaths.select(["docs/setup.md"], paths)

    assert {:ok, ["docs/setup"]} =
             ContentPaths.select(["docs/setup"], Map.put(paths, "docs/setup", true))

    assert {:ok, ["docs/setup.md", "docs/setup.yaml"]} =
             ContentPaths.select(["docs/setu?"], paths)
  end

  test "path seeds are default, top-level paths expand, and explicit node selectors survive" do
    input = %{
      "paths" => ["docs/**/setup?"],
      "seeds" => [%{"value" => "docs/guide"}, %{"id" => "node", "kind" => "id", "value" => "n1"}]
    }

    assert {:ok, result} =
             PathSeeds.resolve(index(["docs/guide.md", "docs/setup1.yaml"]), input)

    assert Enum.map(result["seeds"], & &1["value"]) ==
             ["docs/guide.md", "n1", "docs/setup1.yaml"]

    assert hd(result["seeds"])["kind"] == "path"
    assert {:ok, %{"seeds" => []}} =
             PathSeeds.resolve(index(["docs/guide.md"]), %{"paths" => ["missing/**"]})
  end

  test "resolution uses only supplied authorized paths, including ambiguity detection" do
    unfiltered = %{
      "nodes" => [
        %{"id" => "public", "path" => "public/setup.md"},
        %{"id" => "private", "path" => "private/setup.yaml"},
        %{"id" => "protected", "path" => ".env"}
      ],
      "edges" => [],
      "manifest" => %{}
    }

    authorized = TreeDx.Graph.Filter.authorize(unfiltered, %{"paths" => ["public/**"]}, %{})

    assert {:ok, %{"seeds" => [seed]}} =
             PathSeeds.resolve(authorized, %{"paths" => ["**/setup"]})

    assert seed["value"] == "public/setup.md"
    assert {:ok, %{"seeds" => []}} =
             PathSeeds.resolve(authorized, %{"paths" => ["private/**"]})
  end

  test "rejects traversal, absolute paths, invalid seeds, and oversized expansion" do
    for path <- ["../*", "/docs/*", "docs/%2e%2e/?", "docs\\*", <<0>>] do
      assert {:error, %{code: "validation_error"}} =
               PathSeeds.resolve(index([]), %{"paths" => [path]})
    end

    for seeds <- [[%{}], [false], "invalid"] do
      assert {:error, %{code: "validation_error"}} =
               PathSeeds.resolve(index([]), %{"seeds" => seeds})
    end

    assert {:error, %{code: "validation_error"}} =
             PathSeeds.resolve(index(Enum.map(1..1001, &"docs/#{&1}.md")), %{"paths" => ["**"]})
  end
end
