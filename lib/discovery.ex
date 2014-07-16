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
    find(service, hash),
  ], to: Discovery.Directory

  @doc """
  Select a node providing the given service and run the run fun with that node.
  """
  @spec select(binary, atom | binary, function) :: term | {:error, {:no_servers, binary}}
  def select(service, hash, fun) when is_atom(service), do: select(Atom.to_string(service), hash, fun)
  def select(service, :random, fun) when is_binary(service) and is_function(fun) do
    case nodes(service) do
      [] ->
        fun.({:error, {:no_servers, service}})
      service_nodes ->
        index = :random.uniform(Enum.count(service_nodes))
        fun.({:ok, Enum.at(service_nodes, index - 1)})
    end
  end

  def select(service, hash, fun) when is_binary(service) and is_function(fun) do
    case find(service, hash) do
      {:error, _} ->
        fun.({:error, {:no_servers, service}})
      {:ok, _} = result ->
        fun.(result)
    end
  end
end
