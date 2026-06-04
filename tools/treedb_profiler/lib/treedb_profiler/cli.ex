defmodule TreeDbProfiler.CLI do
  @moduledoc false

  alias TreeDbProfiler.{Report, ScenarioRunner}

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
        IO.puts("TreeDB profile written to #{opts.output}")

        if opts.report_format in ["markdown", "both"] do
          Report.write_markdown!(opts.markdown_output, report)
          IO.puts("TreeDB markdown profile written to #{opts.markdown_output}")
        end

        if opts.include_requests and opts.request_detail_output do
          Report.write_request_details!(opts.request_detail_output, report)
          IO.puts("TreeDB request details written to #{opts.request_detail_output}")
        end

        if get_in(report, ["summary", "totalErrors"]) > 0 or
             get_in(report, ["assertions", "failed"]) > 0 do
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

    normalized = %{
      base_url: Keyword.get(opts, :base_url, "http://localhost:4000"),
      token: Keyword.get(opts, :token),
      auth_mode: Keyword.get(opts, :auth_mode, "dev"),
      fixture: Keyword.get(opts, :fixture, "small-docs"),
      size: Keyword.get(opts, :size, "small"),
      scenario: Keyword.get(opts, :scenario, "full_api"),
      iterations: Keyword.get(opts, :iterations, 1),
      duration: Keyword.get(opts, :duration),
      duration_ms: parse_duration(Keyword.get(opts, :duration)),
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
      profile_id: profile_id,
      repo_prefix: repo_prefix,
      fixture_root:
        Keyword.get(
          opts,
          :fixture_root,
          System.get_env("TREEDB_PROFILER_FIXTURE_ROOT") || "/var/lib/treedb/profiler"
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
         :ok <- validate_positive(normalized.iterations, "iterations"),
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
      {:ok, normalized}
    end
  end

  defp validate_choice(value, allowed, label) do
    if value in allowed,
      do: :ok,
      else: {:error, "--#{label} must be one of #{Enum.join(allowed, ", ")}"}
  end

  defp validate_positive(value, label),
    do: if(value > 0, do: :ok, else: {:error, "--#{label} must be positive"})

  defp validate_non_negative(value, label),
    do: if(value >= 0, do: :ok, else: {:error, "--#{label} must be non-negative"})

  defp parse_duration(nil), do: nil

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

    "treedb-profile-#{timestamp}"
  end

  defp usage do
    """
    Usage:
      treedb_profiler --base-url http://localhost:4000 --auth-mode dev --fixture small-docs --size small --scenario full_api

    Common options:
      --base-url URL
      --token TOKEN
      --auth-mode dev|bearer
      --fixture small-docs|medium-mixed|binary-assets|large-history|graph-rich|workspace-heavy|all
      --size small|medium|large|xl
      --scenario full_api|read_heavy|write_heavy|graph_context|blob_artifact|all
      --load-mode scenario|random|portfolio
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
