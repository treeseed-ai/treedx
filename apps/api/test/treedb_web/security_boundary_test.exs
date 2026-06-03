defmodule TreeDbWeb.SecurityBoundaryTest do
  use TreeDbWeb.ConnCase, async: false

  alias TreeDb.Files.PathPolicy

  test "path policy rejects traversal and protected paths" do
    for path <- ["../secret", "%2e%2e/secret", "docs/../../secret", "/absolute/secret"] do
      assert {:error, %{code: "validation_error"}} = PathPolicy.normalize(path)
    end

    for path <- [".env", ".env.local", "id_rsa", "private.pem", ".ssh/config", ".git/config"] do
      assert PathPolicy.protected?(path)

      assert {:error, %{code: "permission_denied"}} =
               PathPolicy.authorize(workspace(), path, false)
    end
  end

  test "wrong path scope returns sanitized permission error" do
    assert {:error, error} = PathPolicy.authorize(workspace(), "secret/file.md", false)
    assert error.code == "permission_denied"
    refute Jason.encode!(error) =~ "hidden content"
    assert_public_hygiene!(%{ok: false, error: error})
  end

  test "workspace file routes reject traversal without leaking paths", %{conn: conn} do
    data_dir = TreeDb.Store.data_dir()
    repo_path = Path.join(data_dir, "repos/bare/security-boundary")
    create_git_repo!(repo_path)
    token = dev_token!(conn)

    repo =
      register_repo!(build_conn(), token, %{
        "name" => "security-boundary",
        "localPath" => repo_path
      })["repo"]

    workspace =
      create_workspace!(build_conn(), token, repo["repoId"], %{
        "baseRef" => "refs/heads/main",
        "branchName" => "refs/heads/agent/security-boundary",
        "mode" => "writable",
        "allowedPaths" => ["docs/**"]
      })

    for {method, path} <- [
          {:put, "../secret"},
          {:patch, "docs/../../secret"},
          {:delete, "%2e%2e/secret"}
        ] do
      conn = build_conn() |> auth_conn(token)
      route = "/api/v1/workspaces/#{workspace["workspaceId"]}/files?path=#{URI.encode(path)}"

      response =
        conn
        |> request_file_route(method, route)
        |> json_response(422)

      assert response["error"]["code"] == "validation_error"
      assert_public_hygiene!(response)
    end
  end

  defp request_file_route(conn, :put, route), do: put(conn, route, %{"content" => "x"})
  defp request_file_route(conn, :patch, route), do: patch(conn, route, %{"patch" => []})
  defp request_file_route(conn, :delete, route), do: delete(conn, route)

  defp workspace do
    %{
      "effectiveScope" => %{
        "paths" => ["docs/**"],
        "capabilities" => ["files:read", "files:write", "files:delete"],
        "refs" => ["*"],
        "repoIds" => ["*"]
      }
    }
  end
end
