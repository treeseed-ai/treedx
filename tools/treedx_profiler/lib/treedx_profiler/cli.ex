defmodule TreeDxProfiler.CLI do
  @moduledoc false

  alias TreeDxProfiler.{FailureSummary, Report, ScenarioRunner}

  @switches [
    base_url: :string,
    token: :string,
    auth_mode: :string,
    fixture: :string,
    size: :string,
    scenario: :string,
    iterations: :integer,
    duration: :string,
    concurrency: :integer,
    warmup_iterations: :integer,
    timeout_ms: :integer,
    output: :string,
    keep_fixtures: :string,
    cleanup: :string,
    include_admin: :string,
    include_destructive: :string,
    include_exec: :string,
    include_federation: :string,
    metrics: :string,
    load_mode: :string,
    portfolio_initial_repos: :integer,
    portfolio_max_repos: :integer,
    portfolio_create_weight: :integer,
    portfolio_delete_weight: :integer,
    portfolio_growth_target: :string,
    portfolio_repo_prefix: :string,
    portfolio_min_repo_age_before_delete: :string,
    portfolio_max_file_growth_per_repo: :integer,
    portfolio_report_final_state: :string,
    report_format: :string,
    markdown_output: :string,
    include_requests: :string,
    request_sample_limit: :integer,
    request_detail_output: :string,
    state_checks: :string,
    semantic_validation: :string,
    race_policy: :string,
    validation_probes: :string,
    validation_probe_timeout_ms: :integer,
    max_validation_probes_per_request: :integer,
    strict_query_hit_counts: :string,
    strict_graph_expectations: :string,
    strict_snapshot_stability: :string,
    reliability_verifier: :string,
    openapi_response_validation: :string,
    model_reconciliation: :string,
    reconciliation_interval: :string,
    reconciliation_sample_size: :integer,
    operation_chains: :string,
    negative_tests: :string,
    metamorphic_checks: :string,
    delayed_consistency_checks: :string,
    delayed_check_intervals: :string,
    restart_durability_check: :string,
    fault_injection: :string,
    permission_matrix: :string,
    replay_log: :string,
    failure_replay_log: :string,
    request_ledger: :string,
    full_reconciliation_on_finish: :string,
    duration_is_controlling: :string,
    minimum_measured_duration: :string,
    reliability_budget: :string,
    federation_mode: :string,
    federation_node_a_url: :string,
    federation_node_b_url: :string,
    federation_node_c_url: :string,
    federation_node_a_token: :string,
    federation_node_b_token: :string,
    federation_node_c_token: :string,
    federation_exercise_promotion: :string,
    federation_exercise_write_proxy: :string,
    federation_exercise_connected_denials: :string,
    profile_purpose: :string,
    target_primary_rps: :float,
    probe_sampling_rate: :float,
    validation_probe_mode: :string,
    include_probe_samples: :string,
    include_total_throughput: :string,
    performance_workload: :string,
    heavy_operation_rate: :float,
    repo_growth_rate: :float,
    snapshot_rate: :float,
    graph_refresh_rate: :float,
    import_rate: :float,
    fail_below_primary_rps: :float,
    profile_id: :string,
    repo_prefix: :string,
    fixture_root: :string,
    seed: :string,
    fail_fast: :string,
    help: :boolean
  ]

  @aliases [h: :help]

  def main(argv) do
    case parse(argv) do
      {:help, text} ->
        IO.puts(text)

      {:ok, opts} ->
        report = ScenarioRunner.run(opts)
        Report.write!(opts.output, report)
        IO.puts("TreeDX profile written to #{opts.output}")

        if opts.report_format in ["markdown", "both"] do
          Report.write_markdown!(opts.markdown_output, report)
          IO.puts("TreeDX markdown profile written to #{opts.markdown_output}")
        end

        if opts.include_requests and opts.request_detail_output do
          Report.write_request_details!(opts.request_detail_output, report)
          IO.puts("TreeDX request details written to #{opts.request_detail_output}")
        end

        primary_rps = get_in(report, ["throughput", "primary", "requestsPerSecond"]) || 0.0

        below_required_rps? =
          opts.fail_below_primary_rps && primary_rps < opts.fail_below_primary_rps

        if get_in(report, ["summary", "totalErrors"]) > 0 or
             get_in(report, ["assertions", "failed"]) > 0 or
             get_in(report, ["reliabilityBudget", "passed"]) == false or below_required_rps? do
          FailureSummary.print(report, opts)
          System.halt(2)
        end

      {:error, message} ->
        IO.puts(:stderr, message)
        IO.puts(:stderr, usage())
        System.halt(1)
    end
  end

  def parse(argv) do
    case OptionParser.parse(argv, strict: @switches, aliases: @aliases) do
      {opts, [], []} ->
        if Keyword.get(opts, :help, false) do
          {:help, usage()}
        else
          normalize(opts)
        end

      {_opts, _args, invalid} ->
        {:error, "invalid options: #{inspect(invalid)}"}
    end
  end

  defp normalize(opts) do
    profile_id = Keyword.get(opts, :profile_id) || default_profile_id()
    duration = Keyword.get(opts, :duration)
    duration_ms = parse_duration(duration)
    iterations_explicit? = Keyword.has_key?(opts, :iterations)
    iterations = Keyword.get(opts, :iterations)
    duration_controls? = not is_nil(duration_ms) and not iterations_explicit?

    output =
      Keyword.get(opts, :output) ||
        Path.join(["..", "..", "target", "profiles", "#{profile_id}.yaml"])

    markdown_output =
      Keyword.get(opts, :markdown_output) ||
        output
        |> String.replace_suffix(".yaml", ".md")
        |> then(fn path -> if path == output, do: output <> ".md", else: path end)

    repo_prefix = Keyword.get(opts, :repo_prefix, "profile-")
    portfolio_repo_prefix = Keyword.get(opts, :portfolio_repo_prefix, repo_prefix)
    profile_purpose = Keyword.get(opts, :profile_purpose, "reliability")
    default_probe_mode = if profile_purpose == "performance", do: "sampled", else: "all"
    default_probe_sampling = if profile_purpose == "performance", do: 0.10, else: 1.0

    normalized = %{
      base_url: Keyword.get(opts, :base_url, "http://localhost:4000"),
      token: Keyword.get(opts, :token),
      auth_mode: Keyword.get(opts, :auth_mode, "dev"),
      fixture: Keyword.get(opts, :fixture, "small-docs"),
      size: Keyword.get(opts, :size, "small"),
      scenario: Keyword.get(opts, :scenario, "full_api"),
      iterations: iterations,
      iterations_explicit: iterations_explicit?,
      duration: duration,
      duration_ms: duration_ms,
      concurrency: Keyword.get(opts, :concurrency, 1),
      warmup_iterations: Keyword.get(opts, :warmup_iterations, 0),
      timeout_ms: Keyword.get(opts, :timeout_ms, 30_000),
      output: output,
      markdown_output: markdown_output,
      keep_fixtures: parse_bool(Keyword.get(opts, :keep_fixtures), false),
      cleanup: parse_bool(Keyword.get(opts, :cleanup), true),
      include_admin: parse_bool(Keyword.get(opts, :include_admin), false),
      include_destructive: parse_bool(Keyword.get(opts, :include_destructive), false),
      include_exec: parse_bool(Keyword.get(opts, :include_exec), false),
      include_federation: parse_bool(Keyword.get(opts, :include_federation), false),
      metrics: parse_bool(Keyword.get(opts, :metrics), true),
      load_mode: Keyword.get(opts, :load_mode, "random"),
      portfolio_initial_repos: Keyword.get(opts, :portfolio_initial_repos, 1),
      portfolio_max_repos: Keyword.get(opts, :portfolio_max_repos, 1000),
      portfolio_create_weight: Keyword.get(opts, :portfolio_create_weight, 3),
      portfolio_delete_weight: Keyword.get(opts, :portfolio_delete_weight, 1),
      portfolio_growth_target: Keyword.get(opts, :portfolio_growth_target, "steady"),
      portfolio_repo_prefix: portfolio_repo_prefix,
      portfolio_min_repo_age_before_delete:
        parse_duration(Keyword.get(opts, :portfolio_min_repo_age_before_delete, "30m")),
      portfolio_max_file_growth_per_repo:
        Keyword.get(opts, :portfolio_max_file_growth_per_repo, 100_000),
      portfolio_report_final_state:
        parse_bool(Keyword.get(opts, :portfolio_report_final_state), true),
      report_format: Keyword.get(opts, :report_format, "yaml"),
      include_requests: parse_bool(Keyword.get(opts, :include_requests), false),
      request_sample_limit: Keyword.get(opts, :request_sample_limit, 25),
      request_detail_output: Keyword.get(opts, :request_detail_output),
      state_checks: Keyword.get(opts, :state_checks, "api"),
      semantic_validation: parse_bool(Keyword.get(opts, :semantic_validation), true),
      race_policy: Keyword.get(opts, :race_policy, "separate"),
      validation_probes: parse_bool(Keyword.get(opts, :validation_probes), true),
      validation_probe_timeout_ms: Keyword.get(opts, :validation_probe_timeout_ms, 30_000),
      max_validation_probes_per_request: Keyword.get(opts, :max_validation_probes_per_request, 3),
      strict_query_hit_counts: parse_bool(Keyword.get(opts, :strict_query_hit_counts), true),
      strict_graph_expectations: parse_bool(Keyword.get(opts, :strict_graph_expectations), true),
      strict_snapshot_stability: parse_bool(Keyword.get(opts, :strict_snapshot_stability), true),
      reliability_verifier: parse_bool(Keyword.get(opts, :reliability_verifier), true),
      openapi_response_validation:
        parse_bool(Keyword.get(opts, :openapi_response_validation), true),
      model_reconciliation: parse_bool(Keyword.get(opts, :model_reconciliation), true),
      reconciliation_interval: parse_duration(Keyword.get(opts, :reconciliation_interval, "30s")),
      reconciliation_sample_size: Keyword.get(opts, :reconciliation_sample_size, 100),
      operation_chains: parse_bool(Keyword.get(opts, :operation_chains), true),
      negative_tests: parse_bool(Keyword.get(opts, :negative_tests), true),
      metamorphic_checks: parse_bool(Keyword.get(opts, :metamorphic_checks), true),
      delayed_consistency_checks:
        parse_bool(Keyword.get(opts, :delayed_consistency_checks), true),
      delayed_check_intervals:
        parse_duration_list(Keyword.get(opts, :delayed_check_intervals, "5s,30s")),
      restart_durability_check: parse_bool(Keyword.get(opts, :restart_durability_check), false),
      fault_injection: parse_bool(Keyword.get(opts, :fault_injection), false),
      permission_matrix: parse_bool(Keyword.get(opts, :permission_matrix), true),
      replay_log:
        Keyword.get(opts, :replay_log) ||
          Path.join(["..", "..", "target", "profiles", "#{profile_id}-replay.jsonl"]),
      failure_replay_log:
        Keyword.get(opts, :failure_replay_log) ||
          Path.join(["..", "..", "target", "profiles", "#{profile_id}-failures.jsonl"]),
      request_ledger: parse_bool(Keyword.get(opts, :request_ledger), true),
      full_reconciliation_on_finish:
        parse_bool(Keyword.get(opts, :full_reconciliation_on_finish), true),
      duration_is_controlling:
        parse_bool(Keyword.get(opts, :duration_is_controlling), duration_controls?),
      minimum_measured_duration:
        parse_duration(Keyword.get(opts, :minimum_measured_duration)) || duration_ms,
      reliability_budget:
        Keyword.get(
          opts,
          :reliability_budget,
          Path.join([profiler_root(), "reliability_budget.yaml"])
        ),
      federation_mode: Keyword.get(opts, :federation_mode, "single_node"),
      federation_node_a_url: Keyword.get(opts, :federation_node_a_url),
      federation_node_b_url: Keyword.get(opts, :federation_node_b_url),
      federation_node_c_url: Keyword.get(opts, :federation_node_c_url),
      federation_node_a_token: Keyword.get(opts, :federation_node_a_token),
      federation_node_b_token: Keyword.get(opts, :federation_node_b_token),
      federation_node_c_token: Keyword.get(opts, :federation_node_c_token),
      federation_exercise_promotion:
        parse_bool(Keyword.get(opts, :federation_exercise_promotion), false),
      federation_exercise_write_proxy:
        parse_bool(Keyword.get(opts, :federation_exercise_write_proxy), false),
      federation_exercise_connected_denials:
        parse_bool(Keyword.get(opts, :federation_exercise_connected_denials), true),
      profile_purpose: profile_purpose,
      target_primary_rps: Keyword.get(opts, :target_primary_rps),
      probe_sampling_rate: Keyword.get(opts, :probe_sampling_rate, default_probe_sampling),
      validation_probe_mode: Keyword.get(opts, :validation_probe_mode, default_probe_mode),
      include_probe_samples: parse_bool(Keyword.get(opts, :include_probe_samples), false),
      include_total_throughput: parse_bool(Keyword.get(opts, :include_total_throughput), true),
      performance_workload: Keyword.get(opts, :performance_workload, "balanced"),
      heavy_operation_rate: Keyword.get(opts, :heavy_operation_rate, 0.05),
      repo_growth_rate: Keyword.get(opts, :repo_growth_rate, 0.02),
      snapshot_rate: Keyword.get(opts, :snapshot_rate, 0.02),
      graph_refresh_rate: Keyword.get(opts, :graph_refresh_rate, 0.03),
      import_rate: Keyword.get(opts, :import_rate, 0.01),
      fail_below_primary_rps: Keyword.get(opts, :fail_below_primary_rps),
      profile_id: profile_id,
      repo_prefix: repo_prefix,
      fixture_root:
        Keyword.get(
          opts,
          :fixture_root,
          System.get_env("TREEDX_PROFILER_FIXTURE_ROOT") || "/var/lib/treedx/profiler"
        ),
      seed: Keyword.get(opts, :seed),
      fail_fast: parse_bool(Keyword.get(opts, :fail_fast), false)
    }

    with :ok <- validate_choice(normalized.auth_mode, ["dev", "bearer"], "auth-mode"),
         :ok <-
           validate_choice(
             normalized.fixture,
             [
               "small-docs",
               "medium-mixed",
               "binary-assets",
               "large-history",
               "graph-rich",
               "workspace-heavy",
               "all"
             ],
             "fixture"
           ),
         :ok <- validate_choice(normalized.size, ["small", "medium", "large", "xl"], "size"),
         :ok <-
           validate_choice(
             normalized.scenario,
             ["full_api", "read_heavy", "write_heavy", "graph_context", "blob_artifact", "all"],
             "scenario"
           ),
         :ok <-
           validate_choice(normalized.load_mode, ["scenario", "random", "portfolio"], "load-mode"),
         :ok <-
           validate_choice(
             normalized.federation_mode,
             ["single_node", "mirror_cluster", "connected_library"],
             "federation-mode"
           ),
         :ok <-
           validate_choice(
             normalized.profile_purpose,
             ["reliability", "performance", "soak"],
             "profile-purpose"
           ),
         :ok <-
           validate_choice(
             normalized.validation_probe_mode,
             ["all", "sampled", "failures_only", "off"],
             "validation-probe-mode"
           ),
         :ok <-
           validate_choice(
             normalized.performance_workload,
             ["read_mostly", "balanced", "write_mixed", "custom"],
             "performance-workload"
           ),
         :ok <-
           validate_choice(
             normalized.portfolio_growth_target,
             ["sparse", "steady", "aggressive"],
             "portfolio-growth-target"
           ),
         :ok <-
           validate_choice(
             normalized.report_format,
             ["yaml", "markdown", "both"],
             "report-format"
           ),
         :ok <-
           validate_choice(
             normalized.state_checks,
             ["api", "api_with_disk_diagnostics"],
             "state-checks"
           ),
         :ok <-
           validate_choice(
             normalized.race_policy,
             ["separate", "fail", "success"],
             "race-policy"
           ),
         :ok <- validate_optional_positive(normalized.iterations, "iterations"),
         :ok <- validate_positive(normalized.concurrency, "concurrency"),
         :ok <- validate_non_negative(normalized.warmup_iterations, "warmup-iterations"),
         :ok <- validate_positive(normalized.portfolio_initial_repos, "portfolio-initial-repos"),
         :ok <- validate_positive(normalized.portfolio_max_repos, "portfolio-max-repos"),
         :ok <-
           validate_non_negative(normalized.portfolio_create_weight, "portfolio-create-weight"),
         :ok <-
           validate_non_negative(normalized.portfolio_delete_weight, "portfolio-delete-weight"),
         :ok <-
           validate_positive(
             normalized.portfolio_max_file_growth_per_repo,
             "portfolio-max-file-growth-per-repo"
           ),
         :ok <- validate_non_negative(normalized.request_sample_limit, "request-sample-limit") do
      with :ok <-
             validate_positive(
               normalized.validation_probe_timeout_ms,
               "validation-probe-timeout-ms"
             ),
           :ok <-
             validate_positive(
               normalized.max_validation_probes_per_request,
               "max-validation-probes-per-request"
             ),
           :ok <-
             validate_positive(
               normalized.reconciliation_sample_size,
               "reconciliation-sample-size"
             ),
           :ok <- validate_rate(normalized.probe_sampling_rate, "probe-sampling-rate"),
           :ok <-
             validate_non_negative_float(normalized.heavy_operation_rate, "heavy-operation-rate"),
           :ok <- validate_non_negative_float(normalized.repo_growth_rate, "repo-growth-rate"),
           :ok <- validate_non_negative_float(normalized.snapshot_rate, "snapshot-rate"),
           :ok <-
             validate_non_negative_float(normalized.graph_refresh_rate, "graph-refresh-rate"),
           :ok <- validate_non_negative_float(normalized.import_rate, "import-rate"),
           :ok <-
             validate_optional_positive_float(normalized.target_primary_rps, "target-primary-rps"),
           :ok <-
             validate_optional_positive_float(
               normalized.fail_below_primary_rps,
               "fail-below-primary-rps"
             ) do
        {:ok, normalized}
      end
    else
      error -> error
    end
  end

  defp validate_choice(value, allowed, label) do
    if value in allowed,
      do: :ok,
      else: {:error, "--#{label} must be one of #{Enum.join(allowed, ", ")}"}
  end

  defp validate_positive(value, label),
    do: if(value > 0, do: :ok, else: {:error, "--#{label} must be positive"})

  defp validate_optional_positive(nil, _label), do: :ok
  defp validate_optional_positive(value, label), do: validate_positive(value, label)

  defp validate_non_negative(value, label),
    do: if(value >= 0, do: :ok, else: {:error, "--#{label} must be non-negative"})

  defp validate_rate(value, _label) when is_number(value) and value >= 0.0 and value <= 1.0,
    do: :ok

  defp validate_rate(_value, label), do: {:error, "--#{label} must be between 0.0 and 1.0"}

  defp validate_non_negative_float(value, _label) when is_number(value) and value >= 0.0, do: :ok

  defp validate_non_negative_float(_value, label),
    do: {:error, "--#{label} must be non-negative"}

  defp validate_optional_positive_float(nil, _label), do: :ok

  defp validate_optional_positive_float(value, _label) when is_number(value) and value > 0.0,
    do: :ok

  defp validate_optional_positive_float(_value, label),
    do: {:error, "--#{label} must be positive"}

  defp parse_duration(nil), do: nil
  defp parse_duration(""), do: nil

  defp parse_duration(value) do
    case Regex.run(~r/^(\d+)(ms|s|m|h)?$/, value) do
      [_, amount, nil] -> String.to_integer(amount)
      [_, amount, "ms"] -> String.to_integer(amount)
      [_, amount, "s"] -> String.to_integer(amount) * 1000
      [_, amount, "m"] -> String.to_integer(amount) * 60_000
      [_, amount, "h"] -> String.to_integer(amount) * 3_600_000
      _ -> raise ArgumentError, "invalid duration #{inspect(value)}"
    end
  end

  defp parse_duration_list(nil), do: []
  defp parse_duration_list(""), do: []

  defp parse_duration_list(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&parse_duration/1)
  end

  defp parse_bool(nil, default), do: default
  defp parse_bool(value, _default) when value in [true, "true", "1", "yes", "on"], do: true
  defp parse_bool(value, _default) when value in [false, "false", "0", "no", "off"], do: false

  defp parse_bool(value, _default),
    do: raise(ArgumentError, "invalid boolean #{inspect(value)}")

  defp default_profile_id do
    timestamp =
      DateTime.utc_now()
      |> DateTime.to_iso8601(:basic)
      |> String.replace(~r/[^0-9TZ]/, "")

    "treedx-profile-#{timestamp}"
  end

  defp profiler_root do
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

  defp usage do
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
