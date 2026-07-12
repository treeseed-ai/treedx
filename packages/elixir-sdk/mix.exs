defmodule TreeDxSdk.MixProject do
  use Mix.Project

  def project do
    [
      app: :treedx,
      version: "0.2.40",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      description: "Generic Elixir SDK for TreeDX.",
      package: [
        licenses: ["Apache-2.0"],
        links: %{"Repository" => "https://github.com/treeseed-ai/treedx"},
        files: ["lib", "mix.exs", "README.md", "sdk-manifest.yaml"]
      ],
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger, :inets, :ssl]]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:yaml_elixir, "~> 2.11", only: :test}
    ]
  end
end
