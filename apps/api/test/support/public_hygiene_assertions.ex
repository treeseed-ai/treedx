defmodule TreeDxPublicHygieneAssertions do
  @moduledoc false

  import ExUnit.Assertions

  @internal_key_patterns [
    ~r/"localPath"\s*:/,
    ~r/"materializedPath"\s*:/
  ]

  @internal_value_patterns [
    ~r/\/var\/lib\/treedx/,
    ~r/\/tmp\/treedx/,
    ~r/\/tmp\/[^"]*treedx/i
  ]

  @secret_patterns [
    ~r/Bearer\s+[A-Za-z0-9._~+\/=-]+/,
    ~r/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/,
    ~r/TREEDX_[A-Z0-9_]+/,
    ~r/https?:\/\/[^"\s]*((token|secret|password|access_token)=)[^"\s]*/i
  ]

  @leakage_markers [
    "docs/private/hidden.md",
    "hidden repo secret",
    "repo_hidden",
    "secret-bearing"
  ]

  def assert_public_hygiene!(payload) do
    refute_internal_paths!(payload)
    refute_secret_like_values!(payload)
    :ok
  end

  def refute_internal_paths!(payload) do
    json = Jason.encode!(payload)

    for pattern <- @internal_key_patterns ++ @internal_value_patterns do
      refute json =~ pattern,
             "public response leaked internal path data matching #{inspect(pattern)}"
    end
  end

  def refute_secret_like_values!(payload) do
    json = Jason.encode!(payload)

    for pattern <- @secret_patterns do
      refute json =~ pattern,
             "public response leaked secret-like data matching #{inspect(pattern)}"
    end
  end

  def refute_hidden_leakage_markers!(payload) do
    json = Jason.encode!(payload)

    for marker <- @leakage_markers do
      refute json =~ marker, "public response leaked hidden marker #{inspect(marker)}"
    end
  end
end
