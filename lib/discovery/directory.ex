defmodule Discovery.Directory do
  use GenServer
  @name Discovery.Directory

  def start_link do
    Agent.start_link(fn -> %{nodes: %{}, services: %{}} end, name: @name)
  end

  @doc """
  Add a node and the service it provides to the directory.
  """
  def add(node, service) do
    Agent.update(@name, fn(%{nodes: nodes, services: services} = state) ->
      case Dict.fetch(services, service) do
        :error ->
          new_services = Dict.put(services, service, HashSet.new |> Set.put(node))
        {:ok, nodes} ->
          new_services = Dict.put(services, service, Set.put(nodes, node))
      end

      case Dict.fetch(nodes, node) do
        :error ->
          new_nodes = Dict.put(nodes, node, HashSet.new |> Set.put(service))
        {:ok, node_services} ->
          new_nodes = Dict.put(nodes, node, Set.put(node_services, service))
      end

      %{state | nodes: new_nodes, services: new_services}
    end)
  end

  @doc """
  Clear all registered nodes from the directory.
  """
  def clear do
    Agent.update(@name, fn(_) ->
      %{nodes: %{}, services: %{}}
    end)
  end

  @doc """
  Drop a node from the directory.
  """
  def drop(node) do
    Agent.update(@name, fn(%{nodes: nodes, services: services} = state) ->
      case Dict.pop(nodes, node) do
        {nil, new_nodes} ->
          new_nodes    = new_nodes
          new_services = services
        {node_services, new_nodes} ->
          new_nodes    = new_nodes
          new_services = Enum.reduce(services, %{}, fn({key, value}, acc) ->
            new_set = Set.delete(value, node)
            case Enum.empty?(new_set) do
              true ->
                acc
              false ->
                Map.put(acc, key, new_set)
            end
          end)
      end

      %{state | nodes: new_nodes, services: new_services}
    end)
  end

  @doc """
  List all nodes and the services they provide.
  """
  def nodes do
    Agent.get(@name, fn(%{nodes: nodes}) -> nodes end)
  end

  @doc """
  List all nodes which provide a given service.
  """
  def nodes(service) when is_binary(service) do
    GenServer.call(@name, {:nodes, service})
  end

  @doc """
  List all services and the nodes which provide them.
  """
  def services do
    Agent.get(@name, fn(%{services: services}) -> services end)
  end
end
