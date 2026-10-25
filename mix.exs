defmodule Errow.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/kuku/errow"

  def project do
    [
      app: :errow,
      version: @version,
      elixir: ">= 1.14.0",
      start_permanent: Mix.env() == :prod,
      description: "Zero-copy, Apache Arrow-compliant packed arrays for Elixir and the BEAM.",
      package: package(),
      docs: docs(),
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      main: "Errow",
      source_url: @source_url
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end
end
