defmodule Discovery.Directory do
  @moduledoc """
  A registered process that contains the state of known nodes and the services
  that they provide.
  """

  use GenServer
  @name Discovery.Directory

  def start_link do
    Agent.start_link(fn -> %{nodes: %{}, services: %{}} end, name: @name)
  end

  @doc """
  Add a node and the service it provides to the directory.
  """
  @spec add(atom, binary) :: :ok
  def add(node, service) when is_atom(node) and is_binary(service) do
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
  @spec clear :: :ok
  def clear do
    Agent.update(@name, fn(_) ->
      %{nodes: %{}, services: %{}}
    end)
  end

  @doc """
  Drop a node from the directory.
  """
  @spec drop(atom) :: :ok
  def drop(node) when is_atom(node) do
    Agent.update(@name, fn(%{nodes: nodes, services: services} = state) ->
      case Dict.pop(nodes, node) do
        {nil, new_nodes} ->
          new_nodes    = new_nodes
          new_services = services
        {_, new_nodes} ->
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
  Checks if node exists within the Directory.
  """
  @spec has_node?(atom) :: boolean
  def has_node?(node) when is_atom(node) do
    Agent.get(@name, fn(%{nodes: nodes}) ->
      Map.has_key?(nodes, node)
    end)
  end

  @doc """
  List all nodes and the services they provide.
  """
  @spec nodes :: Set.t
  def nodes do
    Agent.get(@name, fn(%{nodes: nodes}) -> nodes end)
  end

  @doc """
  List all nodes which provide the given service.
  """
  @spec nodes(binary) :: list
  def nodes(service) when is_binary(service) do
    Agent.get(@name, fn(%{services: services}) ->
      case Map.fetch(services, service) do
        :error ->
          []
        {:ok, nodes} ->
          Set.to_list(nodes)
      end
    end)
  end

  @doc """
  List all services and the nodes which provide them.
  """
  @spec services :: Set.t
  def services do
    Agent.get(@name, fn(%{services: services}) -> services end)
  end
end
