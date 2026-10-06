defmodule TreeDxProfiler.ReportTest do
  use ExUnit.Case, async: true

  alias TreeDxProfiler.Report

  test "writes yaml report" do
    path =
      Path.join(
        System.tmp_dir!(),
        "treedx-profiler-report-#{System.unique_integer([:positive])}.yaml"
      )

    Report.write!(path, %{"profile" => %{"id" => "test"}, "summary" => %{"totalErrors" => 0}})
    text = File.read!(path)
    assert text =~ "profile:"
    assert text =~ "totalErrors"
    File.rm(path)
  end
end
