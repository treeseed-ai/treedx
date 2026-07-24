defmodule TreeDxProfiler.SemanticExpectationTest do
  use ExUnit.Case, async: true

  alias TreeDxProfiler.SemanticExpectation

  test "builds exact content expectations with hash and unique terms" do
    content = "# Title\n\nprofile_term_000123 release EntityAlpha123\n"

    expectation = SemanticExpectation.content_expectation(content, %{path: "docs/a.md"})

    assert expectation.path == "docs/a.md"
    assert expectation.content == content
    assert expectation.byte_length == byte_size(content)
    assert expectation.sha256 =~ ~r/^[0-9a-f]{64}$/
    assert "profile_term_000123" in expectation.search_terms
    assert "EntityAlpha123" in expectation.search_terms
  end

  test "resolves runtime workspace file expectations" do
    workspace = %{
      written_files: %{
        "workspace/a.md" => %{path: "workspace/a.md", content: "release", sha256: "abc"}
      }
    }

    assert %{content: "release"} =
             SemanticExpectation.file_from_workspace(workspace, "workspace/a.md")

    refute SemanticExpectation.file_from_workspace(workspace, "workspace/missing.md")
  end
end
