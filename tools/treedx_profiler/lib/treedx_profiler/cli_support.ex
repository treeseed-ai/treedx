defmodule TreeDxProfiler.CLISupport do
  @moduledoc false

  def default_profile_id do
    timestamp =
      DateTime.utc_now()
      |> DateTime.to_iso8601(:basic)
      |> String.replace(~r/[^0-9TZ]/, "")

    "treedx-profile-#{timestamp}"
  end

  def profiler_root do
    case System.get_env("TREEDX_PROFILER_ROOT") do
      nil ->
        __ENV__.file
        |> Path.dirname()
        |> Path.join("..")
        |> Path.expand()
        |> Path.dirname()

      root ->
        Path.expand(root)
    end
  end

  def usage do
    """
    Usage:
      treedx_profiler --base-url http://localhost:4000 --auth-mode dev --fixture small-docs --size small --scenario full_api

    Common options:
      --base-url URL
      --token TOKEN
      --auth-mode dev|bearer
      --fixture small-docs|medium-mixed|binary-assets|large-history|graph-rich|workspace-heavy|all
      --size small|medium|large|xl
      --scenario full_api|read_heavy|write_heavy|graph_context|blob_artifact|all
      --load-mode scenario|random|portfolio
      --semantic-validation true|false
      --race-policy separate|fail|success
      --validation-probes true|false
      --validation-probe-timeout-ms N
      --max-validation-probes-per-request N
      --reliability-verifier true|false
      --duration-is-controlling true|false
      --minimum-measured-duration 10m
      --openapi-response-validation true|false
      --model-reconciliation true|false
      --reconciliation-interval 30s
      --negative-tests true|false
      --metamorphic-checks true|false
      --permission-matrix true|false
      --replay-log PATH
      --failure-replay-log PATH
      --federation-mode single_node|mirror_cluster|connected_library
      --federation-node-a-url URL
      --federation-node-b-url URL
      --federation-node-c-url URL
      --federation-exercise-promotion true|false
      --federation-exercise-write-proxy true|false
      --federation-exercise-connected-denials true|false
      --profile-purpose reliability|performance|soak
      --target-primary-rps N
      --probe-sampling-rate FLOAT
      --validation-probe-mode all|sampled|failures_only|off
      --include-total-throughput true|false
      --performance-workload read_mostly|balanced|write_mixed|custom
      --fail-below-primary-rps N
      --iterations N
      --duration 10m
      --concurrency N
      --warmup-iterations N
      --timeout-ms N
      --repo-prefix PREFIX
      --portfolio-repo-prefix PREFIX
      --portfolio-initial-repos N
      --portfolio-max-repos N
      --portfolio-growth-target sparse|steady|aggressive
      --portfolio-min-repo-age-before-delete 30m
      --report-format yaml|markdown|both
      --markdown-output PATH
      --include-requests true|false
      --fixture-root PATH
      --output PATH
    """
  end
end
