defmodule TreeDxProfiler.LeakDetectorTest do
  use ExUnit.Case, async: true

  alias TreeDxProfiler.LeakDetector

  test "portfolio mode treats retained workspaces as expected final state" do
    report =
      LeakDetector.report(%{
        opts: %{cleanup: true, load_mode: "portfolio"},
        portfolio: %{"activeWorkspaces" => 7}
      })

    assert report["warnings"] == []
    assert report["expectedRetainedWorkspaces"] == 7
  end

  test "fixed fixture mode warns when cleanup leaves active workspaces" do
    report =
      LeakDetector.report(%{
        opts: %{cleanup: true, load_mode: "scenario"},
        portfolio: %{"activeWorkspaces" => 1}
      })

    assert [%{"message" => "active workspaces remained after cleanup"}] = report["warnings"]
  end
end
