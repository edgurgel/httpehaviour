defmodule HTTPehaviour.Mixfile do
  use Mix.Project

  @description """
    Yet Yet Another HTTP client for Elixir powered by hackney
  """

  def project do
    [app: :httpehaviour,
     version: "0.9.0",
     elixir: "~> 1.0",
     name: "HTTPehaviour",
     description: @description,
     package: package,
     deps: deps,
     source_url: "https://github.com/edgurgel/httpehaviour"]
  end

  def application do
    [applications: [:hackney]]
  end

  defp deps do
    [{:hackney, "~> 1.0" },
     {:exjsx, "~> 3.1", only: :test},
     {:httparrot, "~> 0.3.4", only: :test},
     {:meck, "~> 0.8.2", only: :test},
     {:earmark, "~> 0.1.17", only: :docs},
     {:ex_doc, "~> 0.8.0", only: :docs}]
  end

  defp package do
    [ contributors: ["Eduardo Gurgel Pinho"],
      licenses: ["MIT"],
      links: %{"Github" => "https://github.com/edgurgel/httpehaviour"} ]
  end
end
