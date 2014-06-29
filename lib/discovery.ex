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
  def select(service, hash, fun) when is_binary(service) and is_function(fun) do
    case select_node(service, hash) do
      {:ok, node} ->
        fun.(node)
      error ->
        error
    end
  end

  #
  # Private API
  #

  defp select_node(service, :random) do
    case nodes(service) do
      [] ->
        {:error, {:no_servers, service}}
      service_nodes ->
        index = :random.uniform(Enum.count(service_nodes))
        {:ok, Enum.at(service_nodes, index - 1)}
    end
  end

  defp select_node(service, _hash) do
    case nodes(service) do
      [] ->
        {:error, {:no_servers, service}}
      service_nodes ->
        # JW TODO: determine best server instead of picking first one
        {:ok, Enum.first(service_nodes)}
    end
  end
end
