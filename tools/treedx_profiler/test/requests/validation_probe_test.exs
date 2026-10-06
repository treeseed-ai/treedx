defmodule TreeDxProfiler.ValidationProbeTest do
  use ExUnit.Case, async: true

  alias TreeDxProfiler.{ProfileRequest, ValidationProbe}

  test "does not run probes when disabled" do
    request =
      ProfileRequest.new(%{
        id: "req_1",
        operation_id: "writeWorkspaceFile",
        operation_type: :write,
        method: :put,
        path_template: "/api/v1/workspaces/{workspace_id}/files",
        path: "/api/v1/workspaces/ws_1/files",
        category: "workspace",
        expected_status: [200],
        validation_rule: "workspace_read_after_write",
        validation_probes: [%{kind: :workspace_file_content_equals}],
        seed: "seed"
      })

    state = %{opts: %{validation_probes: false}}

    assert %{samples: [], failures: []} = ValidationProbe.run(state, request, %{})
  end
end
