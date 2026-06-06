defmodule TreeDxProfiler.PermissionMatrixTest do
  use ExUnit.Case, async: true

  alias TreeDxProfiler.PermissionMatrix

  test "does not count exec-disabled responses as permission matrix failures" do
    samples = [
      %{
        category: "exec",
        operation_id: "execWorkspace",
        status: 403,
        error_code: nil
      },
      %{
        category: "policy",
        operation_id: "listCapabilityGrants",
        status: 200,
        error_code: nil
      }
    ]

    report = PermissionMatrix.report(samples, %{permission_matrix: true, include_exec: false})

    assert report["total"] == 1
    assert report["failed"] == 0
  end

  test "counts unsanitized authorization failures" do
    samples = [
      %{
        category: "repository",
        operation_id: "readRepositoryFile",
        status: 403,
        error_code: nil
      }
    ]

    report = PermissionMatrix.report(samples, %{permission_matrix: true, include_exec: true})

    assert report["total"] == 1
    assert report["failed"] == 1
  end
end
