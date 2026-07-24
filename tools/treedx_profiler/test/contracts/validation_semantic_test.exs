defmodule TreeDxProfiler.ValidationSemanticTest do
  use ExUnit.Case, async: true

  alias TreeDxProfiler.{Hash, ProfileRequest, Validation}

  test "exact file content validation detects mismatch" do
    request =
      ProfileRequest.new(%{
        id: "req_1",
        operation_id: "readRepositoryFile",
        operation_type: :read,
        method: :post,
        path_template: "/api/v1/repos/{repo_id}/files/read",
        path: "/api/v1/repos/repo_1/files/read",
        category: "repository_read",
        expected_status: [200],
        validation_rule: "file_content_matches_expectation",
        target: %{path: "docs/a.md"},
        expectation: %{path: "docs/a.md", content: "expected", sha256: Hash.sha256("expected")},
        seed: "seed"
      })

    ctx = %{request: request, state: %{fixture: %{expected: %{known: %{}}}}, sample: %{}}

    assert :ok =
             Validation.validate(
               "file_content_matches_expectation",
               Map.put(ctx, :response, %{
                 "ok" => true,
                 "file" => %{"path" => "docs/a.md", "content" => "expected"}
               })
             )

    assert {:error, message} =
             Validation.validate(
               "file_content_matches_expectation",
               Map.put(ctx, :response, %{
                 "ok" => true,
                 "file" => %{"path" => "docs/a.md", "content" => "wrong"}
               })
             )

    assert message =~ "content mismatch"
  end

  test "search validation requires expected generated path when provided" do
    request =
      ProfileRequest.new(%{
        id: "req_2",
        operation_id: "searchRepositoryFiles",
        operation_type: :query,
        method: :post,
        path_template: "/api/v1/repos/{repo_id}/files/search",
        path: "/api/v1/repos/repo_1/files/search",
        category: "repository_read",
        expected_status: [200],
        validation_rule: "search_hits_expected_terms",
        expectation: %{expected_path: "docs/expected.md"},
        seed: "seed"
      })

    ctx = %{request: request, state: %{fixture: %{expected: %{}}}, sample: %{}}

    assert {:error, message} =
             Validation.validate(
               "search_hits_expected_terms",
               Map.put(ctx, :response, %{
                 "ok" => true,
                 "results" => [%{"path" => "docs/other.md"}]
               })
             )

    assert message =~ "missing expected path"
  end
end
