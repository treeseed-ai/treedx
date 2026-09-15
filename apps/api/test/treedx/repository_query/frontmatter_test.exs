defmodule TreeDx.RepositoryQuery.FrontmatterTest do
  use ExUnit.Case, async: true

  alias TreeDx.RepositoryQuery.Frontmatter

  test "preserves printable Unicode frontmatter strings as strings" do
    document =
      Frontmatter.parse("""
      ---
      rationale: "The SDK’s proposal can’t lose Unicode text."
      ---

      Body
      """)

    assert document.frontmatter["rationale"] == "The SDK’s proposal can’t lose Unicode text."
    assert document.frontmatterError == nil
  end
end
