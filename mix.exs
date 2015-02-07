defmodule Discovery.Mixfile do
  use Mix.Project

  def project do
    [
      app: :discovery,
      version: "0.5.7",
      elixir: "~> 1.0 or ~> 0.15.1",
      deps: deps,
      package: package,
      description: description
    ]
  end

  def application do
    [
      mod: {Discovery, []},
      applications: [
        :consul,
        :hash_ring_ex,
        :logger,
      ],
      registered: [
        Discovery.Directory,
        Discovery.NodeConnector,
      ],
      env: [
        retry_connect_ms: 5000,
        replica_count: 128,
        enable_polling: true,
      ]
    ]
  end

  defp deps do
    [
      {:consul, "~> 1.0"},
      {:hash_ring_ex, "~> 1.1"},
      {:inch_ex, only: :docs}
    ]
  end

  defp description do
    """
    An OTP application for auto-discovering services with Consul
    """
  end

  defp package do
    %{licenses: ["MIT"],
      contributors: ["Jamie Winsor"],
      links: %{"Github" => "https://github.com/undeadlabs/discovery"}}
  end
end
