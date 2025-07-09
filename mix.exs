defmodule Mabeam.MixProject do
  use Mix.Project

  def project do
    [
      app: :mabeam,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Mabeam.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Core dependencies
      {:jason, "~> 1.4"},
      {:telemetry, "~> 1.2"},
      {:phoenix_pubsub, "~> 2.1"},
      {:nimble_options, "~> 1.0"},
      {:typed_struct, "~> 0.3.0"},
      {:elixir_uuid, "~> 1.2"},

      # Development and testing
      {:ex_doc, "~> 0.27", only: :dev, runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev], runtime: false},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:stream_data, "~> 0.5", only: :test}
    ]
  end
end
