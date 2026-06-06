defmodule TreeDxTestFixtures do
  @moduledoc false

  import Phoenix.ConnTest
  import Plug.Conn

  @endpoint TreeDxWeb.Endpoint

  def create_git_repo!(path, opts \\ []) do
    File.rm_rf!(path)
    File.mkdir_p!(path)

    git!(path, ["init", "-b", "main"])
    git!(path, ["config", "user.name", "TreeDX Test"])
    git!(path, ["config", "user.email", "test@example.invalid"])

    write!(path, "README.md", """
    ---
    title: Root Readme
    status: published
    tags:
      - mvp
    ---
    # Root

    Root fixture for mvp provenance.
    """)

    write!(path, "docs/readme.md", """
    ---
    title: MVP Readme
    status: published
    tags:
      - mvp
      - provenance
    updated_at: 2026-06-01T00:00:00Z
    ---
    # MVP Provenance

    This document contains the unique phrase mvp provenance.

    See [Guide](guide.md) and [Other Repo](treedx://repo/repo_b/docs/other.md).
    """)

    write!(path, "docs/guide.md", """
    ---
    title: Guide
    status: published
    tags: guide
    ---
    # Guide

    Linked guide content for mvp provenance.
    """)

    write!(path, "docs/private/hidden.md", """
    ---
    title: Hidden
    status: private
    ---
    # Hidden

    Hidden file that must not leak from restricted scopes.
    """)

    write!(path, "src/content/notes/alpha.mdx", """
    ---
    title: Alpha Note
    status: published
    tags:
      - alpha
    ---
    import Beta from './beta.mdx'

    # Alpha

    Alpha MDX body mentions mvp provenance.
    """)

    write!(path, "src/content/notes/beta.mdx", """
    ---
    title: Beta Note
    status: published
    ---
    # Beta

    Beta MDX body.
    """)

    write!(path, "src/content/notes/draft.mdx", """
    ---
    title: Draft Note
    status: draft
    ---
    # Draft

    Draft content outside limited docs scope.
    """)

    write!(path, "src/content/pages/home.md", """
    ---
    title: Home
    status: published
    ---
    # Home

    Home page fixture.
    """)

    write!(path, "plain/search.txt", "plain text mvp provenance fixture\n")

    write!(path, "package.json", """
    {
      "scripts": {
        "test": "node -e \\"process.exit(0)\\""
      }
    }
    """)

    git!(path, ["add", "."])
    git!(path, ["commit", "-m", Keyword.get(opts, :message, "Initial fixture")])
    git!(path, ["tag", "v1"])

    path
  end

  def dev_token!(conn, opts \\ %{}) do
    conn
    |> post("/api/v1/auth/dev-token", Map.new(opts))
    |> json!(200)
    |> Map.fetch!("accessToken")
  end

  def auth_conn(conn, token) do
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  def register_repo!(conn, token, attrs) do
    conn
    |> auth_conn(token)
    |> post("/api/v1/repos/register", attrs)
    |> json!(200)
  end

  def create_workspace!(conn, token, repo_id, attrs) do
    conn
    |> auth_conn(token)
    |> post("/api/v1/repos/#{repo_id}/workspaces", attrs)
    |> json!(200)
  end

  def create_mirror!(conn, token, repo_id, attrs) do
    conn
    |> auth_conn(token)
    |> post("/api/v1/repos/#{repo_id}/mirrors", attrs)
    |> json!(200)
  end

  def json!(conn, status) do
    Phoenix.ConnTest.json_response(conn, status)
  end

  def git!(cwd, args) do
    {output, status} = System.cmd("git", args, cd: cwd, stderr_to_stdout: true)

    if status == 0 do
      output
    else
      raise "git #{Enum.join(args, " ")} failed in #{cwd}:\n#{output}"
    end
  end

  defp write!(root, path, content) do
    full_path = Path.join(root, path)
    File.mkdir_p!(Path.dirname(full_path))
    File.write!(full_path, content)
  end
end
