defmodule TreeDxProfiler.TemplateTest do
  use ExUnit.Case, async: true

  alias TreeDxProfiler.Template

  test "renders known path variables" do
    state = state()

    assert Template.render_path("/api/v1/repos/{repo_id}/files/read", state) ==
             "/api/v1/repos/repo_1/files/read"
  end

  test "renders request body values" do
    body =
      Template.render_body(
        %{"ref" => "{primary_ref}", "path" => "{known_markdown_path}"},
        state()
      )

    assert body == %{"ref" => "refs/heads/main", "path" => "docs/topic-01/doc-000001.md"}
  end

  test "missing variables return unavailable marker" do
    assert Template.render_path("/{missing}", state()) == {:unavailable, "missing missing"}
  end

  defp state do
    %{
      workspace_id: "ws_1",
      fixture: %{
        local_repos: [
          %{repo_id: "repo_1", branches: ["refs/heads/fixture/branch-001"]}
        ],
        expected: %{
          known: %{
            markdown_path: "docs/topic-01/doc-000001.md",
            text_path: "plain/group-01/text-000001.txt",
            json_path: "data/group-01/item-000001.json",
            binary_path: "assets/blob/blob-000001.bin",
            search_term: "release",
            context_query: "release"
          },
          workspace: %{
            write_targets: ["workspace/write-000001.md"],
            patch_targets: ["workspace/patch-000001.md"],
            delete_targets: ["workspace/delete-000001.md"]
          }
        }
      }
    }
  end
end
