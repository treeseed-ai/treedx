defmodule TreeDxProfiler.ScenarioReport do
  @moduledoc false

  alias TreeDxProfiler.{
    DelayedCheckScheduler,
    EndpointConsistency,
    EndpointMatrix,
    FaultInjection,
    LeakDetector,
    MetamorphicChecker,
    ModelState,
    NegativeRequestGenerator,
    OpenApiResponseValidator,
    OperationChain,
    PermissionMatrix,
    Reconciler,
    ReliabilityBudget,
    ReplayLog,
    RestartDurability,
    Stats,
    SystemProfile
  }

  def build(state, started) do
    operations = Stats.aggregate(state.samples)
    assertions = assertion_summary(state.assertions)
    http_samples = measured_http_samples(state)

    coverage =
      EndpointMatrix.coverage(state.samples, state.opts, state[:covered_operation_ids] || [])

    summary = Stats.summary(state.samples, operations)
    throughput = Stats.throughput_breakdown(state.samples, http_samples, state.opts)
    model = ModelState.from_state(state)
    openapi_validation = OpenApiResponseValidator.report(state.assertions)

    report = %{
      "profile" => %{
        "id" => state.opts.profile_id,
        "generatedAt" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "startedAt" => DateTime.to_iso8601(started),
        "endedAt" => get_in(state, [:timing, "profile", "endedAt"]),
        "tool" => %{"name" => "treedx_profiler", "version" => TreeDxProfiler.version()}
      },
      "target" => %{"baseUrl" => state.opts.base_url},
      "environment" => SystemProfile.collect(),
      "timing" => timing_report(state),
      "workload" => %{
        "loadMode" => state.opts.load_mode,
        "fixture" => state.opts.fixture,
        "size" => state.opts.size,
        "scenario" => state.opts.scenario,
        "repoPrefix" => state.opts.repo_prefix,
        "portfolioRepoPrefix" => state.opts.portfolio_repo_prefix,
        "portfolioInitialRepos" => state.opts.portfolio_initial_repos,
        "portfolioMaxRepos" => state.opts.portfolio_max_repos,
        "portfolioGrowthTarget" => state.opts.portfolio_growth_target,
        "iterations" => state.opts.iterations,
        "iterationsExplicit" => state.opts.iterations_explicit,
        "durationMs" => state.opts.duration_ms,
        "durationIsControlling" => state.opts.duration_is_controlling,
        "minimumMeasuredDurationMs" => state.opts.minimum_measured_duration,
        "concurrency" => state.opts.concurrency,
        "warmupIterations" => state.opts.warmup_iterations,
        "reportFormat" => state.opts.report_format,
        "includeRequests" => state.opts.include_requests,
        "requestSampleLimit" => state.opts.request_sample_limit,
        "stateChecks" => state.opts.state_checks,
        "includeAdmin" => state.opts.include_admin,
        "includeDestructive" => state.opts.include_destructive,
        "includeExec" => state.opts.include_exec,
        "includeFederation" => state.opts.include_federation,
        "federationMode" => state.opts.federation_mode
      },
      "operationMix" => TreeDxProfiler.ScenarioReportMetrics.operation_mix_report(state.opts),
      "validation" => %{
        "semanticValidation" => state.opts.semantic_validation,
        "validationProbes" => state.opts.validation_probes,
        "validationProbeMode" => state.opts.validation_probe_mode,
        "probeSamplingRate" => state.opts.probe_sampling_rate,
        "strictQueryHitCounts" => state.opts.strict_query_hit_counts,
        "strictGraphExpectations" => state.opts.strict_graph_expectations,
        "strictSnapshotStability" => state.opts.strict_snapshot_stability,
        "reliabilityVerifier" => state.opts.reliability_verifier,
        "openapiResponseValidation" => state.opts.openapi_response_validation,
        "modelReconciliation" => state.opts.model_reconciliation
      },
      "fixtures" => fixture_report(state.fixture),
      "coverage" => coverage,
      "metrics" => %{
        "before" => state[:metrics_before] || %{},
        "after" => state[:metrics_after] || %{},
        "delta" => %{}
      },
      "operations" => operations,
      "categories" => Stats.category_aggregates(operations),
      "operationTypes" => Stats.operation_type_aggregates(operations),
      "throughput" => throughput,
      "resourceTuning" => TreeDxProfiler.ScenarioReportMetrics.resource_tuning_report(state),
      "serverRuntime" => TreeDxProfiler.ScenarioReportMetrics.server_runtime_report(state),
      "cache" => TreeDxProfiler.ScenarioReportMetrics.cache_report(state),
      "workerPools" => TreeDxProfiler.ScenarioReportMetrics.worker_pool_report(state),
      "saturation" => Stats.saturation_report(state.samples),
      "federationLoadBalancing" => federation_load_balancing_report(state),
      "portfolio" => state[:portfolio] || %{},
      "federation" => state[:federation] || %{"mode" => state.opts.federation_mode},
      "modelState" => ModelState.report(model),
      "reconciliation" => Reconciler.final_report(state, model),
      "operationChains" => OperationChain.report(state.samples, state.opts),
      "negativeTests" => NegativeRequestGenerator.report(state, state.opts),
      "metamorphic" => MetamorphicChecker.report(state.samples, state.opts),
      "delayedConsistency" => DelayedCheckScheduler.report(state.assertions, state.opts),
      "restartDurability" => RestartDurability.report(state.opts),
      "faultInjection" => FaultInjection.report(state.opts),
      "endpointConsistency" => EndpointConsistency.report(state.samples, state, state.opts),
      "openapiValidation" => openapi_validation,
      "replay" => ReplayLog.report(state.opts),
      "leakDetection" => LeakDetector.report(state),
      "permissionMatrix" => PermissionMatrix.report(state.samples, state.opts),
      "scheduler" => state[:scheduler] || %{},
      "validationProbes" => validation_probe_report(state.assertions, http_samples, state.opts),
      "concurrency" => concurrency_report(state[:portfolio_runtime], state.opts),
      "requestSamples" => state[:request_samples] || %{"failures" => [], "successes" => %{}},
      "errors" => error_report(state.samples),
      "assertions" => assertions,
      "summary" => summary
    }

    Map.put(report, "reliabilityBudget", ReliabilityBudget.evaluate(report, state.opts))
  end

  defp timing_report(state) do
    timing = state[:timing] || %{}

    %{
      "profile" => Map.get(timing, "profile", %{}),
      "setup" => Map.get(timing, "setup", %{}),
      "measured" =>
        Map.merge(
          %{
            "requestedDurationMs" => state.opts.duration_ms,
            "durationSatisfied" => is_nil(state.opts.duration_ms)
          },
          Map.get(timing, "measured", %{})
        ),
      "cleanup" => Map.get(timing, "cleanup", %{})
    }
  end

  defp error_report(samples) do
    errors = Enum.filter(samples, &(&1.ok != true and &1.assertion != :race_interference))

    %{
      "total" => length(errors),
      "byOperation" =>
        errors
        |> Enum.group_by(& &1.operation_id)
        |> Enum.map(fn {operation, values} -> {operation, length(values)} end)
        |> Map.new(),
      "samples" =>
        errors
        |> Enum.take(100)
        |> Enum.map(fn sample ->
          %{
            "operationId" => sample.operation_id,
            "status" => sample.status,
            "errorCode" => sample.error_code,
            "pathTemplate" => sample.path_template,
            "elapsedMs" => sample.duration_ms,
            "validation" => to_string(sample.assertion)
          }
        end)
    }
  end

  defp measured_http_samples(state) do
    samples = state[:http_samples] || state.samples
    measured = get_in(state, [:timing, "measured"]) || %{}
    started_at = measured["startedAt"]
    ended_at = measured["endedAt"]

    Enum.filter(samples, fn sample ->
      Map.get(sample, :counts_toward_total_http_rps, true) == true and
        Map.get(sample, :measured_window, :measured) == :measured and
        sample_in_measured_window?(sample, started_at, ended_at)
    end)
  end

  defp sample_in_measured_window?(_sample, nil, _ended_at), do: true
  defp sample_in_measured_window?(_sample, _started_at, nil), do: true

  defp sample_in_measured_window?(sample, started_at, ended_at) do
    with {:ok, sample_dt, _} <- DateTime.from_iso8601(sample.started_at),
         {:ok, start_dt, _} <- DateTime.from_iso8601(started_at),
         {:ok, end_dt, _} <- DateTime.from_iso8601(ended_at) do
      DateTime.compare(sample_dt, start_dt) != :lt and DateTime.compare(sample_dt, end_dt) != :gt
    else
      _ -> true
    end
  end

  defp validation_probe_report(samples_or_assertions, http_samples, opts)

  defp validation_probe_report(assertions, http_samples, opts) when is_list(assertions) do
    probe_samples =
      Enum.filter(http_samples, &(Map.get(&1, :sample_kind) == :validation_probe))

    total = Enum.sum(Enum.map(assertions, &(Map.get(&1, :validationProbes, 0) || 0)))
    total = max(total, length(probe_samples))

    failed =
      case probe_samples do
        [] ->
          assertions
          |> Enum.filter(&(Map.get(&1, :validationProbes, 0) > 0 and &1.passed == false))
          |> length()

        samples ->
          Enum.count(samples, &(&1.ok != true))
      end

    %{
      "total" => total,
      "failed" => failed,
      "samplingRate" => Map.get(opts, :probe_sampling_rate),
      "mode" => Map.get(opts, :validation_probe_mode),
      "samplesRetained" => length(probe_samples),
      "byOperation" =>
        assertions
        |> Enum.group_by(&operation_id_for/1)
        |> Enum.map(fn {operation, values} ->
          probes = Enum.sum(Enum.map(values, &(Map.get(&1, :validationProbes, 0) || 0)))

          failures =
            Enum.count(values, &(Map.get(&1, :validationProbes, 0) > 0 and &1.passed == false))

          {operation, %{"probes" => probes, "failed" => failures}}
        end)
        |> Map.new()
    }
  end

  defp federation_load_balancing_report(state) do
    counters =
      get_in(state, [:metrics_after, "counters"]) || get_in(state, [:metrics_after, :counters]) ||
        []

    spillovers = metric_sum(counters, "treedx_federation_read_spillover_total")
    failures = metric_sum(counters, "treedx_federation_read_spillover_failures_total")

    %{
      "enabled" =>
        System.get_env("TREEDX_FEDERATION_LOAD_AWARE_READS", "true") not in ["false", "0"],
      "readSpillovers" => spillovers,
      "failures" => failures,
      "byTargetNode" =>
        counters
        |> Enum.filter(
          &(Map.get(&1, :name) == "treedx_federation_read_spillover_total" or
              Map.get(&1, "name") == "treedx_federation_read_spillover_total")
        )
        |> Enum.reduce(%{}, fn counter, acc ->
          labels = Map.get(counter, :labels) || Map.get(counter, "labels") || %{}
          node = labels[:target_node] || labels["target_node"] || "unknown"
          Map.update(acc, node, counter_value(counter), &(&1 + counter_value(counter)))
        end)
    }
  end

  defp metric_sum(counters, name) do
    counters
    |> Enum.filter(&(Map.get(&1, :name) == name or Map.get(&1, "name") == name))
    |> Enum.map(&counter_value/1)
    |> Enum.sum()
  end

  defp counter_value(counter), do: Map.get(counter, :value) || Map.get(counter, "value") || 0

  defp operation_id_for(assertion) do
    assertion[:operationId] || assertion[:operation_id] || assertion["operationId"] ||
      assertion["operation_id"] || "unknown"
  end

  defp concurrency_report(nil, opts) do
    %{
      "racePolicy" => opts.race_policy,
      "raceInterference" => %{
        "total" => 0,
        "verified" => 0,
        "unverified" => 0,
        "byOperation" => %{},
        "byCause" => %{},
        "samples" => []
      }
    }
  end

  defp concurrency_report(snapshot, opts) do
    races = Map.get(snapshot, :races, [])

    %{
      "racePolicy" => opts.race_policy,
      "raceInterference" => %{
        "total" => length(races),
        "verified" => Enum.count(races, &(Map.get(&1, :raceVerified) == true)),
        "unverified" => Enum.count(races, &(Map.get(&1, :raceVerified) != true)),
        "byOperation" => count_by(races, & &1.operationId),
        "byCause" => count_by(races, & &1.likelyCause),
        "samples" => Enum.take(races, 100)
      }
    }
  end

  defp count_by(values, fun) do
    values
    |> Enum.reduce(%{}, fn value, acc ->
      Map.update(acc, fun.(value) || "unknown", 1, &(&1 + 1))
    end)
  end

  defp fixture_report(fixture) do
    registered_by_name = Map.new(fixture.local_repos, &{&1.name, Map.has_key?(&1, :repo_id)})

    %{
      "families" =>
        Enum.map(fixture.families || [], fn family ->
          defn = family.definition

          %{
            "id" => family.fixture_id,
            "size" => family.size,
            "reposCreated" => length(family.repos),
            "reposRegistered" =>
              Enum.count(family.repos, &Map.get(registered_by_name, &1.name, false)),
            "files" => %{
              "markdown" => defn.markdown,
              "text" => defn.text,
              "json" => defn.json,
              "binary" => defn.binary
            },
            "history" => %{
              "branches" => defn.branches,
              "commits" => defn.commits
            },
            "graph" => %{
              "linksPerDoc" => defn.links_per_doc,
              "sectionsPerDoc" => defn.sections_per_doc
            }
          }
        end),
      "repos" => %{
        "created" => length(fixture.local_repos),
        "registered" => Enum.count(fixture.local_repos, &Map.has_key?(&1, :repo_id))
      },
      "files" => stringify_keys(fixture.expected.file_counts),
      "expected" => %{
        "searchTerms" => fixture.expected.search_hits,
        "graph" => %{
          "minNodes" => fixture.expected.graph.min_nodes,
          "minEdges" => fixture.expected.graph.min_edges,
          "expectedSections" => fixture.expected.graph.expected_sections,
          "expectedEntities" => fixture.expected.graph.expected_entities
        }
      }
    }
  end

  defp assertion_summary(assertions) do
    races = Enum.filter(assertions, &(Map.get(&1, :status) == :race_interference))
    failures = Enum.reject(assertions, &(&1.passed or Map.get(&1, :status) == :race_interference))

    %{
      "passed" => Enum.count(assertions, & &1.passed),
      "failed" => length(failures),
      "raceInterference" => length(races),
      "unavailable" => Enum.count(assertions, &(Map.get(&1, :status) == :unavailable)),
      "failures" => Enum.map(failures, &Map.new(&1))
    }
  end

  defp stringify_keys(map),
    do: map |> Enum.map(fn {key, value} -> {to_string(key), value} end) |> Map.new()
end
