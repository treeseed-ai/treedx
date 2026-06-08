defmodule TreeDx.MixProject do
  use Mix.Project

  def project do
    [
      app: :treedx,
      version: "0.1.6",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  def application do
    [
      mod: {TreeDx.Application, []},
      extra_applications: [:logger, :runtime_tools, :inets, :ssl, :public_key]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix, "~> 1.8.7"},
      {:jason, "~> 1.4"},
      {:bandit, "~> 1.8"},
      {:rustler, "~> 0.38.0"},
      {:yamerl, "~> 0.10"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get"],
      test: ["test"]
    ]
  end
end
