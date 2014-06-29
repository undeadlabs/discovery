defmodule Discovery do
  use Application

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    children = [
      worker(Discovery.Directory, []),
      worker(Discovery.NodeConnector, []),
    ]

    opts = [strategy: :one_for_one, name: Discovery.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defdelegate [
    nodes(service),
  ], to: Discovery.Directory

  @doc """
  Select a node providing the given service and run the run fun with that node.
  """
  @spec select(binary, atom | binary, function) :: term | {:error, {:no_servers, binary}}
  def select(service, :random, fun) when is_binary(service) and is_function(fun) do
    case nodes(service) do
      [] ->
        fun.({:error, {:no_servers, service}})
      service_nodes ->
        index = :random.uniform(Enum.count(service_nodes))
        fun.({:ok, Enum.at(service_nodes, index - 1)})
    end
  end

  def select(service, _hash, fun) when is_binary(service) and is_function(fun) do
    case nodes(service) do
      [] ->
        fun.({:error, {:no_servers, service}})
      service_nodes ->
        # JW TODO: determine best server instead of picking first one
        fun.({:ok, List.first(service_nodes)})
    end
  end
end
