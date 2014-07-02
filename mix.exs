defmodule Discovery.Mixfile do
  use Mix.Project

  def project do
    [app: :discovery,
     version: "0.0.1",
     elixir: "~> 0.13",
     config_path: "config/#{Mix.env}.exs",
     deps: deps]
  end

  def application do
    [
      mod: {Discovery, []},
      applications: [
        :consul,
        :hash_ring_ex,
      ],
      registered: [
        Discovery.Directory,
        Discovery.NodeConnector,
      ],
      env: [
        retry_connect_ms: 5000,
        replica_count: 128,
      ]
    ]
  end

  defp deps do
    [
      {:consul, git: "git@github.com:undeadlabs/consul-ex.git"},
      {:hash_ring_ex, "~> 1.0"},
    ]
  end
end
