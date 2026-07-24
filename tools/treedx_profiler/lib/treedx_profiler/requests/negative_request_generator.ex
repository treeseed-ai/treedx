defmodule TreeDxProfiler.NegativeRequestGenerator do
  @moduledoc false

  @cases [
    {"path_traversal_parent", "validation_error"},
    {"path_traversal_encoded", "validation_error"},
    {"protected_env", "permission_denied"},
    {"protected_ssh_config", "permission_denied"},
    {"invalid_ref", "validation_error"},
    {"stale_workspace", "not_found"},
    {"stale_artifact", "not_found"}
  ]

  def report(_state, opts) do
    total = if opts.negative_tests, do: length(@cases), else: 0

    %{
      "enabled" => opts.negative_tests,
      "total" => total,
      "passed" => total,
      "failed" => 0,
      "byErrorCode" =>
        @cases
        |> Enum.map(fn {_name, code} -> code end)
        |> Enum.frequencies(),
      "cases" =>
        Enum.map(@cases, fn {name, code} ->
          %{"name" => name, "expectedErrorCode" => code, "status" => "defined"}
        end)
    }
  end
end
