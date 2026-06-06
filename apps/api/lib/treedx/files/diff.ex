defmodule TreeDx.Files.Diff do
  @moduledoc false

  def unified(path, old_content, new_content) do
    old_lines = String.split(old_content || "", "\n")
    new_lines = String.split(new_content || "", "\n")

    body =
      if old_lines == new_lines do
        []
      else
        ["@@ -1,#{length(old_lines)} +1,#{length(new_lines)} @@"] ++
          Enum.map(old_lines, &("-" <> &1)) ++ Enum.map(new_lines, &("+" <> &1))
      end

    Enum.join(["diff --git a/#{path} b/#{path}", "--- a/#{path}", "+++ b/#{path}" | body], "\n") <>
      "\n"
  end
end
