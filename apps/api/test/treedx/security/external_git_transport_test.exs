defmodule TreeDx.ExternalGitTransportTest do
  use ExUnit.Case, async: false

  setup do
    names = ["TREEDX_GIT_EXTERNAL_TRANSPORT_ENABLED", "TREEDX_GIT_ALLOWED_HOSTS"]
    original = Map.new(names, &{&1, System.get_env(&1)})
    System.put_env("TREEDX_GIT_EXTERNAL_TRANSPORT_ENABLED", "true")
    System.put_env("TREEDX_GIT_ALLOWED_HOSTS", "github.com")

    on_exit(fn ->
      Enum.each(original, fn
        {name, nil} -> System.delete_env(name)
        {name, value} -> System.put_env(name, value)
      end)
    end)

    :ok
  end

  test "plans one HTTPS ref with an exact expected remote head" do
    input = %{
      repoPath: System.tmp_dir!(),
      remoteUrl: "https://github.com/example/project.git",
      remoteName: "origin",
      refspecs: ["refs/heads/reviewed:refs/heads/staging"],
      expectedRemoteHead: String.duplicate("a", 40),
      planOnly: true
    }

    assert {:ok, result} = TreeDx.Git.ExternalTransport.push(input, %{"token" => "canary"})
    assert result["status"] == "plan"
    assert result["beforeHead"] == String.duplicate("a", 40)
    refute inspect(result) =~ "canary"
  end

  test "fails closed for SSH, unlisted hosts, missing leases, and multiple refs" do
    base = %{
      repoPath: System.tmp_dir!(),
      remoteName: "origin",
      planOnly: true,
      expectedRemoteHead: "",
      refspecs: ["refs/heads/reviewed:refs/heads/staging"]
    }

    assert {:error, %{code: "unsupported_transport"}} =
             TreeDx.Git.ExternalTransport.push(
               Map.put(base, :remoteUrl, "git@github.com:example/project.git"),
               %{"token" => "token"}
             )

    assert {:error, %{code: "permission_denied"}} =
             TreeDx.Git.ExternalTransport.push(
               Map.put(base, :remoteUrl, "https://example.invalid/project.git"),
               %{"token" => "token"}
             )

    assert {:error, %{code: "validation_error"}} =
             TreeDx.Git.ExternalTransport.push(
               Map.merge(base, %{
                 remoteUrl: "https://github.com/example/project.git",
                 expectedRemoteHead: nil
               }),
               %{"token" => "token"}
             )

    assert {:error, %{code: "validation_error"}} =
             TreeDx.Git.ExternalTransport.push(
               Map.merge(base, %{
                 remoteUrl: "https://github.com/example/project.git",
                 refspecs: base.refspecs ++ ["refs/heads/other:refs/heads/other"]
               }),
               %{"token" => "token"}
             )
  end

  test "rejects wildcard, deleting, and non-ref fetch refspecs before invoking Git" do
    base = %{
      repoPath: System.tmp_dir!(),
      remoteUrl: "https://github.com/example/project.git",
      remoteName: "origin"
    }

    for refspecs <- [
          ["+refs/heads/*:refs/remotes/origin/*"],
          ["refs/heads/main:"],
          ["main:refs/remotes/origin/main"],
          ["refs/heads/main:refs/heads/../outside"],
          ["refs/heads/main:refs/heads/main.lock"]
        ] do
      assert {:error, %{code: "validation_error"}} =
               TreeDx.Git.ExternalTransport.fetch(
                 Map.put(base, :refspecs, refspecs),
                 %{"token" => "token"}
               )
    end
  end

  test "routes public HTTPS fetches through the bounded external transport without a credential" do
    assert TreeDx.Git.ExternalTransport.required?("https://github.com/example/project.git")

    assert {:ok, result} =
             TreeDx.Git.ExternalTransport.fetch(
               %{
                 repoPath: System.tmp_dir!(),
                 remoteUrl: "https://github.com/example/project.git",
                 remoteName: "origin",
                 refspecs: ["+refs/heads/staging:refs/heads/staging"],
                 planOnly: true
               },
               nil
             )

    assert result["status"] == "plan"
  end
end
