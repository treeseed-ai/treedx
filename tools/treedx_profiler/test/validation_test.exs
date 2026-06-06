defmodule TreeDxProfiler.ValidationTest do
  use ExUnit.Case, async: true

  alias TreeDxProfiler.Validation

  test "file content validation passes for generated release content" do
    ctx = ctx(%{"ok" => true, "file" => %{"content" => "release provenance"}})
    assert :ok = Validation.validate("file_content_matches_expectation", ctx)
  end

  test "blob validation detects error envelopes" do
    ctx = ctx(%{"ok" => false, "error" => %{"code" => "validation_error"}})
    assert {:error, _} = Validation.validate("blob_hash_matches_expectation", ctx)
  end

  test "sanitization validation detects local paths" do
    ctx = ctx(%{"ok" => true, "path" => "/tmp/secret"})
    assert {:error, _} = Validation.validate("storage_response_sanitized", ctx)
  end

  test "unknown validation rule fails" do
    assert {:error, message} = Validation.validate("missing_rule", ctx(%{"ok" => true}))
    assert message =~ "unknown"
  end

  defp ctx(response) do
    %{
      response: response,
      state: %{
        fixture: %{
          expected: %{
            known: %{markdown_path: "docs/topic-01/doc-000001.md"}
          },
          local_repos: [%{repo_id: "repo_1"}]
        }
      },
      sample: %{},
      operation: %{}
    }
  end
end
