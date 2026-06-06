defmodule TreeDxProfiler.ProbePolicyTest do
  use ExUnit.Case, async: true

  alias TreeDxProfiler.ProbePolicy

  test "reliability mode runs all successful probes" do
    assert ProbePolicy.run_success_probes?(
             opts("reliability", "all", 1.0),
             request("readRepositoryFile")
           )
  end

  test "performance mode samples ordinary successful probes" do
    refute ProbePolicy.run_success_probes?(
             opts("performance", "sampled", 0.0),
             request("readRepositoryFile")
           )
  end

  test "performance mode keeps state-transition probes for mutating operations" do
    assert ProbePolicy.run_success_probes?(
             opts("performance", "sampled", 0.0),
             request("writeWorkspaceFile")
           )
  end

  test "off mode disables probes" do
    refute ProbePolicy.run_success_probes?(
             opts("performance", "off", 1.0),
             request("writeWorkspaceFile")
           )
  end

  defp opts(profile_purpose, mode, rate) do
    %{
      profile_purpose: profile_purpose,
      validation_probes: true,
      validation_probe_mode: mode,
      probe_sampling_rate: rate
    }
  end

  defp request(operation_id) do
    %{id: "req_1", operation_id: operation_id, seed: "seed"}
  end
end
