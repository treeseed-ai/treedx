defmodule TreeDx.Observability.ScrubberTest do
  use ExUnit.Case, async: true

  alias TreeDx.Observability.Scrubber

  test "redacts bearer tokens, JWTs, credential URLs, env secrets, and paths" do
    payload = %{
      authorization: "Bearer abc.def.ghi",
      jwt: "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.sig",
      remoteUrl: "https://user:pass@example.test/repo.git",
      env: "TREEDX_JWT_HS256_SECRET",
      localPath: "/var/lib/treedx/catalog/manifest.tdb",
      tempPath: "/tmp/treedx-secret/file"
    }

    scrubbed = Scrubber.scrub(payload)
    encoded = Jason.encode!(scrubbed)

    refute encoded =~ "abc.def.ghi"
    refute encoded =~ "eyJ"
    refute encoded =~ "user:pass"
    refute encoded =~ "TREEDX_JWT_HS256_SECRET"
    refute encoded =~ "/var/lib/treedx"
    refute encoded =~ "/tmp/"
  end

  test "keeps safe logical identifiers and bounded labels" do
    payload = %{repoId: "repo_1", workspaceId: "ws_1", operation: "repo.show", status: "ok"}
    assert Scrubber.scrub(payload) == payload

    labels =
      Scrubber.scrub_labels(%{
        method: "GET",
        route: "/api/v1/repos/:repo_id",
        actorId: "actor_secret",
        authorization: "Bearer token"
      })

    assert labels == %{"method" => "GET", "route" => "/api/v1/repos/:repo_id"}
  end
end
