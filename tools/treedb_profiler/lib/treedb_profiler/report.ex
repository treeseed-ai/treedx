defmodule TreeDbProfiler.Report do
  @moduledoc false

  def write!(path, report) do
    File.mkdir_p!(Path.dirname(path))
    yaml = Ymlr.document!(report)
    File.write!(path, yaml)
  end

  def write_markdown!(path, report) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, TreeDbProfiler.MarkdownReport.render(report))
  end

  def write_request_details!(path, report) do
    File.mkdir_p!(Path.dirname(path))
    yaml = Ymlr.document!(Map.get(report, "requestSamples", %{}))
    File.write!(path, yaml)
  end
end
