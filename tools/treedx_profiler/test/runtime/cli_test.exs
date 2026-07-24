defmodule TreeDxProfiler.CLITest do
  use ExUnit.Case, async: true

  alias TreeDxProfiler.CLI

  test "parses defaults" do
    assert {:ok, opts} = CLI.parse([])
    assert opts.base_url == "http://localhost:4000"
    assert opts.auth_mode == "dev"
    assert opts.fixture == "small-docs"
    assert opts.size == "small"
    assert opts.repo_prefix == "profile-"
    assert opts.portfolio_repo_prefix == "profile-"
    assert opts.scenario == "full_api"
    assert opts.load_mode == "random"
    assert opts.report_format == "yaml"
    assert opts.iterations == nil
    assert opts.iterations_explicit == false
    assert opts.concurrency == 1
    assert opts.reliability_verifier
    assert opts.openapi_response_validation
  end

  test "parses duration and explicit settings" do
    assert {:ok, opts} =
             CLI.parse([
               "--base-url",
               "http://example.test",
               "--auth-mode",
               "bearer",
               "--token",
               "token",
               "--fixture",
               "medium-mixed",
               "--size",
               "large",
               "--repo-prefix",
               "test-",
               "--iterations",
               "10",
               "--duration",
               "5m",
               "--concurrency",
               "4"
             ])

    assert opts.base_url == "http://example.test"
    assert opts.fixture == "medium-mixed"
    assert opts.size == "large"
    assert opts.repo_prefix == "test-"
    assert opts.duration_ms == 300_000
    assert opts.iterations == 10
    assert opts.iterations_explicit
    assert opts.duration_is_controlling == false
    assert opts.concurrency == 4
  end

  test "duration controls measured load when iterations are not explicit" do
    assert {:ok, opts} = CLI.parse(["--duration", "10m"])
    assert opts.iterations == nil
    assert opts.duration_ms == 600_000
    assert opts.duration_is_controlling
    assert opts.minimum_measured_duration == 600_000
  end

  test "parses portfolio mode options" do
    assert {:ok, opts} =
             CLI.parse([
               "--load-mode",
               "portfolio",
               "--portfolio-initial-repos",
               "2",
               "--portfolio-max-repos",
               "50",
               "--portfolio-growth-target",
               "aggressive",
               "--portfolio-repo-prefix",
               "test-",
               "--portfolio-min-repo-age-before-delete",
               "5m",
               "--report-format",
               "both",
               "--include-requests",
               "true",
               "--request-sample-limit",
               "10"
             ])

    assert opts.load_mode == "portfolio"
    assert opts.portfolio_initial_repos == 2
    assert opts.portfolio_max_repos == 50
    assert opts.portfolio_growth_target == "aggressive"
    assert opts.portfolio_repo_prefix == "test-"
    assert opts.portfolio_min_repo_age_before_delete == 300_000
    assert opts.report_format == "both"
    assert opts.include_requests
    assert opts.request_sample_limit == 10
  end

  test "rejects invalid fixture" do
    assert {:error, message} = CLI.parse(["--fixture", "missing"])
    assert message =~ "--fixture"
  end
end
