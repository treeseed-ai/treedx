defmodule TreeDxProfiler.FailureSummary do
  @moduledoc false

  @max_items 5

  def lines(report, opts \\ %{}) do
    []
    |> add_total_errors(report)
    |> add_assertion_failures(report)
    |> add_reliability_budget(report)
    |> add_rps_failure(report, opts)
    |> add_request_failures(report)
    |> Enum.reverse()
  end

  def print(report, opts \\ %{}) do
    case lines(report, opts) do
      [] ->
        :ok

      lines ->
        IO.puts(:stderr, "TreeDX profile failed policy checks:")
        Enum.each(lines, &IO.puts(:stderr, &1))
    end
  end

  defp add_total_errors(lines, report) do
    total = get_in(report, ["summary", "totalErrors"]) || 0

    if total > 0 do
      by_operation =
        report
        |> get_in(["errors", "byOperation"])
        |> format_top_map()

      ["- total errors: #{total}#{by_operation}" | lines]
    else
      lines
    end
  end

  defp add_assertion_failures(lines, report) do
    failed = get_in(report, ["assertions", "failed"]) || 0
    failures = get_in(report, ["assertions", "failures"]) || []

    cond do
      failed <= 0 ->
        lines

      failures == [] ->
        ["- assertion failures: #{failed}" | lines]

      true ->
        details =
          failures
          |> Enum.take(@max_items)
          |> Enum.map(&format_assertion_failure/1)
          |> Enum.join("; ")

        suffix = more_suffix(failures)
        ["- assertion failures: #{failed}: #{details}#{suffix}" | lines]
    end
  end

  defp add_reliability_budget(lines, report) do
    budget = report["reliabilityBudget"] || %{}
    violations = budget["violations"] || []

    if budget["passed"] == false do
      details =
        violations
        |> Enum.take(@max_items)
        |> Enum.map(&format_violation/1)
        |> Enum.join("; ")

      suffix = more_suffix(violations)

      message =
        if details == "",
          do: "- reliability budget failed",
          else: "- reliability budget failed: #{details}#{suffix}"

      [message | lines]
    else
      lines
    end
  end

  defp add_rps_failure(lines, report, opts) do
    required = Map.get(opts, :fail_below_primary_rps)
    actual = get_in(report, ["throughput", "primary", "requestsPerSecond"]) || 0.0

    if required && actual < required do
      ["- primary RPS below threshold: actual #{actual}, required #{required}" | lines]
    else
      lines
    end
  end

  defp add_request_failures(lines, report) do
    failures = get_in(report, ["requestSamples", "failures"]) || []

    if failures == [] do
      lines
    else
      details =
        failures
        |> Enum.take(@max_items)
        |> Enum.map(&format_request_failure/1)
        |> Enum.join("; ")

      suffix = more_suffix(failures)
      ["- retained failure samples: #{details}#{suffix}" | lines]
    end
  end

  defp format_assertion_failure(failure) do
    operation = field(failure, "operation_id") || field(failure, "operationId") || "unknown"
    rule = field(failure, "rule") || field(failure, "validationRule") || "unknown_rule"
    message = field(failure, "message") || field(failure, "error")

    [operation, rule, message]
    |> Enum.reject(&blank?/1)
    |> Enum.join(" ")
  end

  defp format_violation(violation) do
    key = field(violation, "key") || "unknown"
    actual = field(violation, "actual")
    limit = field(violation, "limit")
    operation = field(violation, "operationId")
    category = field(violation, "category")

    context =
      [category, operation]
      |> Enum.reject(&blank?/1)
      |> Enum.join("/")

    threshold =
      if is_nil(actual) and is_nil(limit),
        do: "",
        else: " actual #{inspect(actual)}, limit #{inspect(limit)}"

    if context == "", do: "#{key}#{threshold}", else: "#{key} #{context}#{threshold}"
  end

  defp format_request_failure(sample) do
    operation = field(sample, "operationId") || field(sample, "operation_id") || "unknown"
    status = field(sample, "status")
    error_code = field(sample, "errorCode") || field(sample, "error_code")
    assertion = field(sample, "assertion")

    [operation, "status=#{status}", "error=#{error_code}", "assertion=#{assertion}"]
    |> Enum.reject(&blank?/1)
    |> Enum.join(" ")
  end

  defp format_top_map(nil), do: ""
  defp format_top_map(map) when map == %{}, do: ""

  defp format_top_map(map) when is_map(map) do
    summary =
      map
      |> Enum.sort_by(fn {_key, value} -> value end, :desc)
      |> Enum.take(@max_items)
      |> Enum.map(fn {key, value} -> "#{key}=#{value}" end)
      |> Enum.join(", ")

    " (#{summary})"
  end

  defp format_top_map(_), do: ""

  defp more_suffix(items) when length(items) > @max_items,
    do: "; +#{length(items) - @max_items} more"

  defp more_suffix(_items), do: ""

  defp field(map, key) when is_map(map) do
    Map.get(map, key) || existing_atom_field(map, key)
  end

  defp field(_map, _key), do: nil

  defp existing_atom_field(map, key) do
    Map.get(map, String.to_existing_atom(key))
  rescue
    ArgumentError -> nil
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false
end
