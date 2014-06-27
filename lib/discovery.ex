defmodule Discovery do
  use Application

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    children = [
      worker(Discovery.NodeConnector, [])
    ]

    opts = [strategy: :one_for_one, name: Discovery.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defdelegate [
    nodes(),
    nodes(service)
  ], to: Discovery.NodeConnector
end
