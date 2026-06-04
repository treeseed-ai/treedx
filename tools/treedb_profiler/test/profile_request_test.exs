defmodule TreeDbProfiler.ProfileRequestTest do
  use ExUnit.Case, async: true

  alias TreeDbProfiler.ProfileRequest

  test "creates reusable request metadata" do
    request =
      ProfileRequest.new(%{
        id: "req_1",
        operation_id: "writeWorkspaceFile",
        operation_type: :write,
        method: :put,
        path_template: "/api/v1/workspaces/{workspace_id}/files",
        path: "/api/v1/workspaces/ws_1/files?path=x.md",
        category: "workspace",
        body: %{"content" => "release"},
        expected_status: [200],
        validation_rule: "workspace_read_after_write",
        seed: "seed"
      })

    assert request.operation_id == "writeWorkspaceFile"
    assert request.headers == []
    assert request.state_effect == nil

    assert ProfileRequest.to_meta(request, "full_api", "small-docs") == %{
             operation_id: "writeWorkspaceFile",
             path_template: "/api/v1/workspaces/{workspace_id}/files",
             category: "workspace",
             scenario: "full_api",
             fixture: "small-docs"
           }
  end
end
