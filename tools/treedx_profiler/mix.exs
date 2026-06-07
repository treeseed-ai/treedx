defmodule TreeDxProfiler.MixProject do
  use Mix.Project

  def project do
    [
      app: :treedx_profiler,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      escript: [main_module: TreeDxProfiler.CLI],
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :inets, :ssl, :public_key]
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:req, "~> 0.5"},
      {:yamerl, "~> 0.10"},
      {:ymlr, "~> 5.0"}
    ]
  end
end
