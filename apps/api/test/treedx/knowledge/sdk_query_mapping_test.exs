defmodule TreeDx.SdkQueryMappingTest do
  use ExUnit.Case, async: true

  alias TreeDx.RepositoryQuery.{Filters, Sort}

  test "SDK-style content entries can be assembled from generic TreeDX documents" do
    document = %{
      "path" => "src/content/pages/home.md",
      "frontmatter" => %{"title" => "Home", "status" => "published", "priority" => 2},
      "body" => "Body text",
      "score" => 1
    }

    entry = %{
      "path" => document["path"],
      "frontmatter" => document["frontmatter"],
      "body" => document["body"],
      "title" => Filters.read_field(document, "title")
    }

    assert entry["title"] == "Home"
    assert entry["body"] == "Body text"
    assert entry["frontmatter"]["status"] == "published"
  end

  test "SDK filter and sort specs map to generic TreeDX document fields" do
    docs = [
      %{
        "path" => "b.md",
        "frontmatter" => %{"status" => "draft", "priority" => 1},
        "body" => "two"
      },
      %{
        "path" => "a.md",
        "frontmatter" => %{"status" => "published", "priority" => 2},
        "body" => "one"
      }
    ]

    {:ok, filtered} =
      Filters.apply(docs, [
        %{"field" => "status", "op" => "eq", "value" => "published"},
        %{"field" => "body", "op" => "contains", "value" => "one"}
      ])

    {:ok, sorted} = Sort.apply(filtered, [%{"field" => "path", "direction" => "asc"}])

    assert Enum.map(sorted, & &1["path"]) == ["a.md"]
  end
end
