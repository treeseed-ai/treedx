defmodule TreeDbWeb.SecurityFederationTest do
  use TreeDbWeb.ConnCase, async: false

  test "remote federation failures are sanitized" do
    error = %{
      ok: true,
      search: %{
        query: "release",
        results: [],
        page: %{limit: 20, hasMore: false, cursor: nil},
        diagnostics: %{
          requestedRepoCount: 1,
          executedRepoCount: 0,
          rejectedRepoCount: 0,
          partialFailureCount: 1,
          routing: [
            %{
              repoId: "repo_visible",
              nodeId: "node_remote",
              source: "remote",
              status: "partial_failure",
              error: %{code: "federated_node_unavailable"}
            }
          ]
        },
        errors: [
          %{
            repoId: "repo_visible",
            nodeId: "node_remote",
            code: "federated_node_unavailable",
            message: "Federated node was unavailable."
          }
        ]
      }
    }

    assert_public_hygiene!(error)
    refute Jason.encode!(error) =~ "https://"
    refute Jason.encode!(error) =~ "docs/private"
    refute Jason.encode!(error) =~ "response body"
  end
end
