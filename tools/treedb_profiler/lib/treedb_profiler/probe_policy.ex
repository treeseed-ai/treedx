defmodule TreeDbProfiler.ProbePolicy do
  @moduledoc false

  @always_probe_performance MapSet.new([
                              "writeWorkspaceFile",
                              "patchWorkspaceFile",
                              "deleteWorkspaceFile",
                              "commitWorkspace",
                              "uploadWorkspaceBlob",
                              "downloadWorkspaceBlob",
                              "buildSnapshot",
                              "exportArtifact"
                            ])

  def run_success_probes?(opts, request) do
    cond do
      opts.validation_probes == false ->
        false

      opts.validation_probe_mode == "off" ->
        false

      opts.validation_probe_mode == "failures_only" ->
        false

      opts.validation_probe_mode == "all" ->
        true

      request.operation_id in @always_probe_performance ->
        true

      true ->
        sampled?(request, opts.probe_sampling_rate || 0.0)
    end
  end

  def run_failure_probes?(opts, _request) do
    opts.validation_probes != false and opts.validation_probe_mode != "off"
  end

  defp sampled?(_request, rate) when rate >= 1.0, do: true
  defp sampled?(_request, rate) when rate <= 0.0, do: false

  defp sampled?(request, rate) do
    basis = "#{request.id}:#{request.operation_id}:#{request.seed}"
    <<int::32, _::binary>> = :crypto.hash(:sha256, basis)
    int / 0xFFFFFFFF <= rate
  end
end
