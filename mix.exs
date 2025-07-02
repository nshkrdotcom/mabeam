defmodule Mabeam.MixProject do
  use Mix.Project

  def project do
    [
      app: :mabeam,
      version: "0.0.1",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      name: "Mabeam",
      source_url: "https://github.com/nshkrdotcom/mabeam",
      homepage_url: "https://github.com/nshkrdotcom/mabeam",
      docs: [
        main: "readme",
        extras: ["README.md"]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, "~> 0.28", only: :dev, runtime: false}
    ]
  end

  defp description do
    """
    A multi-agent framework for the BEAM (Erlang VM) that provides agent lifecycle management,
    message passing, discovery, and extensibility for building distributed agent-based systems.
    """
  end

  defp package do
    [
      name: "mabeam",
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/nshkrdotcom/mabeam"
      },
      maintainers: ["NSHkr"]
    ]
  end
end
