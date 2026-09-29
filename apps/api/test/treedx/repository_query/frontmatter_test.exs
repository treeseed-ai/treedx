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

  test "preserves a long Unicode estimate rationale as a string" do
    rationale =
      String.duplicate("The engineer’s estimate includes reasoning and verification. ", 20)

    document =
      Frontmatter.parse(
        "---\nexecutionPlan:\n  workItems:\n    - estimate:\n        rationale: #{rationale}\n---\n\nBody\n"
      )

    assert document.frontmatter["executionPlan"]["workItems"] == [
             %{"estimate" => %{"rationale" => rationale}}
           ]

    assert document.frontmatterError == nil
  end
end
