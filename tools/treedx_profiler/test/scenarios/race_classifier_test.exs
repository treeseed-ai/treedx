defmodule TreeDxProfiler.RaceClassifierTest do
  use ExUnit.Case, async: true

  alias TreeDxProfiler.{ProfileRequest, RaceClassifier}

  test "classifies workspace generation changes as race interference" do
    request =
      ProfileRequest.new(%{
        id: "req_1",
        operation_id: "writeWorkspaceFile",
        operation_type: :write,
        method: :put,
        path_template: "/api/v1/workspaces/{workspace_id}/files",
        path: "/api/v1/workspaces/ws_1/files",
        category: "workspace",
        expected_status: [200, 409],
        validation_rule: "workspace_read_after_write",
        target: %{workspace_id: "ws_1", path: "workspace/a.md"},
        race_context: %{acceptable_statuses: [409]},
        precondition: %{workspace_generation: 1, workspace_open?: true},
        seed: "seed"
      })

    sample = %{status: 409, error_code: "conflict"}

    assert {:race, race} =
             RaceClassifier.classify(%{
               request: request,
               sample: sample,
               response: %{"ok" => false},
               precondition: request.precondition,
               current_state: %{workspace_generation: 2, workspace_open?: true},
               validation_error: "conflict",
               worker_id: 4
             })

    assert race.classification == "race_interference"
    assert race.likelyCause == "workspace_changed_by_another_worker"
    assert race.workerId == 4
  end

  test "does not classify ordinary semantic mismatch as race" do
    request =
      ProfileRequest.new(%{
        id: "req_2",
        operation_id: "readRepositoryFile",
        operation_type: :read,
        method: :post,
        path_template: "/api/v1/repos/{repo_id}/files/read",
        path: "/api/v1/repos/repo_1/files/read",
        category: "repository_read",
        expected_status: [200],
        validation_rule: "file_content_matches_expectation",
        target: %{repo_id: "repo_1", path: "docs/a.md"},
        race_context: %{acceptable_statuses: []},
        precondition: %{repo_generation: 1, repo_deleted?: false},
        seed: "seed"
      })

    assert {:ok, :not_race} =
             RaceClassifier.classify(%{
               request: request,
               sample: %{status: 200, error_code: nil},
               response: %{},
               precondition: request.precondition,
               current_state: request.precondition,
               validation_error: "content mismatch"
             })
  end
end
