#
# The MIT License (MIT)
#
# Copyright (c) 2014-2015 Undead Labs, LLC
#

defmodule Discovery.Directory do
  @moduledoc """
  A registered process that contains the state of known nodes and the services
  that they provide.
  """

  use GenServer
  @name Discovery.Directory

  def start_link do
    GenServer.start_link(__MODULE__, :ok, name: @name)
  end

  @doc """
  Add a node and the service it provides to the directory.
  """
  @spec add(node, binary) :: :ok
  def add(node, service) when is_atom(node) and is_binary(service) do
    GenServer.call(@name, {:add, node, service})
  end

  @doc """
  Add a node and the service it provides to a remote node's directory.
  """
  @spec add(node, node, binary | [binary]) :: :ok | {:error, term}
  def add(_, _, []), do: :ok
  def add(remote, local, [app|rest]) do
    case add(remote, local, app) do
      :ok   -> add(remote, local, rest)
      error -> error
    end
  end
  def add(remote, local, service) when is_atom(local) and is_binary(service) do
    try do
      GenServer.call({@name, remote}, {:add, local, service})
    catch
      :exit, reason -> {:error, reason}
    end
  end

  @doc false
  def clear do
    GenServer.call(@name, :clear)
  end

  @doc """
  Completely remove a node from the directory and all services it provides.
  """
  @spec drop(atom) :: :ok
  def drop(node) when is_atom(node) do
    GenServer.call(@name, {:drop, node})
  end

  @doc """
  Drop the service provided by a node from the directory. If this is the last
  service the node was providing it will be completely removed.
  """
  @spec drop(atom, [binary]) :: :ok
  def drop(node, services) when is_atom(node) and is_list(services) do
    GenServer.call(@name, {:drop, node, services})
  end
  def drop(node, service) when is_binary(service), do: drop(node, [service])

  @doc """
  Find a node running service hashed by hash.
  """
  @spec find(binary, binary) :: {:ok, node} | {:error, term}
  def find(service, hash) do
    GenServer.call(@name, {:find, service, hash})
  end

  @doc """
  Returns true if the given node is known.
  """
  @spec has_node?(atom) :: boolean
  def has_node?(node) when is_atom(node) do
    GenServer.call(@name, {:has_node?, node})
  end

  @doc """
  Returns true if the given node is known and providing the given service and
  false if the node is not known or not providing the service.
  """
  @spec has_node?(atom, binary) :: boolean
  def has_node?(node, service) when is_atom(node) and is_binary(service) do
    GenServer.call(@name, {:has_node?, node, service})
  end

  @doc """
  List all nodes and the services they provide.
  """
  @spec nodes :: map
  def nodes do
    GenServer.call(@name, :nodes)
  end

  @doc """
  List all nodes which provide the given service.
  """
  @spec nodes(binary | [binary]) :: list
  def nodes(services) when is_list(services) do
    Enum.reduce(services, [], fn(service, acc) -> nodes(service) ++ acc end)
  end
  def nodes(service) when is_binary(service) do
    GenServer.call(@name, {:nodes, service})
  end

  @doc """
  List all services and the nodes which provide them.
  """
  @spec services :: map
  def services do
    GenServer.call(@name, :services)
  end

  @doc """
  List all services that a given node provides.
  """
  @spec services(atom) :: [binary]
  def services(node) do
    GenServer.call(@name, {:services, node})
  end

  def rings do
    GenServer.call(@name, :rings)
  end

  #
  # Private API
  #

  defp start_ring do
    {:ok, pid} = Discovery.Ring.start
    ref        = Process.monitor(pid)
    %Discovery.Ring{pid: pid, ref: ref}
  end

  def stop_ring(%Discovery.Ring{pid: pid, ref: ref}) do
    Process.demonitor(ref, [:flush])
    Discovery.Ring.stop(pid)
  end

  #
  # GenServer callbacks
  #

  def init(:ok) do
    {:ok, %{nodes: %{}, services: %{}, rings: %{}}}
  end

  def handle_call({:add, node, service}, _, %{nodes: nodes, services: services, rings: rings} = state) do
    ring = 
    case Dict.fetch(rings, service) do
      {:ok, ring} -> ring
      :error -> start_ring
    end

    :ok = Discovery.Ring.add(ring.pid, node)

    new_services =
    case Dict.fetch(services, service) do
      :error ->
        Dict.put(services, service, HashSet.new |> Set.put(node))
      {:ok, nodes} ->
        Dict.put(services, service, Set.put(nodes, node))
    end

    new_nodes =
    case Dict.fetch(nodes, node) do
      :error ->
        Dict.put(nodes, node, HashSet.new |> Set.put(service))
      {:ok, node_services} ->
        Dict.put(nodes, node, Set.put(node_services, service))
    end

    {:reply, :ok, %{state | nodes: new_nodes, services: new_services, rings: Dict.put(rings, service, ring)}}
  end

  def handle_call(:clear, _, %{rings: rings}) do
    Enum.each(rings, fn({_, ring}) -> stop_ring(ring) end)
    {:reply, :ok, %{nodes: %{}, services: %{}, rings: %{}}}
  end

  def handle_call({:drop, node}, _, state) do
    new_state = _drop(node, state)
    {:reply, :ok, new_state}
  end

  def handle_call({:drop, node, services}, _, state) do
    new_state = _drop(node, services, state)
    {:reply, :ok, new_state}
  end

  def handle_call({:find, service, hash}, _, %{rings: rings} = state) do
    case Dict.fetch(rings, service) do
      {:ok, %Discovery.Ring{pid: ring}} ->
        {:reply, Discovery.Ring.find(ring, hash), state}
      :error ->
        {:reply, {:error, :unknown_service}, state}
    end
  end

  def handle_call({:has_node?, node}, _, %{nodes: nodes} = state) do
    {:reply, Dict.has_key?(nodes, node), state}
  end

  def handle_call({:has_node?, node, service}, _, %{nodes: nodes} = state) do
    result = Enum.any?(nodes, fn({name, services}) ->
      name == node && Set.member?(services, service)
    end)
    {:reply, result, state}
  end

  def handle_call(:nodes, _, %{nodes: nodes} = state) do
    {:reply, nodes, state}
  end

  def handle_call({:nodes, service}, _, %{services: services} = state) do
    case Dict.fetch(services, service) do
      :error ->
        {:reply, [], state}
      {:ok, nodes} ->
        {:reply, Set.to_list(nodes), state}
    end
  end

  def handle_call(:services, _, %{services: services} = state) do
    {:reply, services, state}
  end

  def handle_call({:services, node}, _, %{nodes: nodes} = state) do
    case Dict.get(nodes, node) do
      nil ->
        {:reply, nil, state}
      services ->
        {:reply, Dict.to_list(services), state}
    end
  end

  def handle_call(:rings, _, %{rings: rings} = state) do
    {:reply, rings, state}
  end

  def handle_info({:DOWN, ref, _, _, _}, %{rings: rings, services: services} = state) do
    {service, _} = Enum.find(rings, fn({_, %Discovery.Ring{ref: lref}}) -> lref == ref end)
    %Discovery.Ring{pid: pid} = new_ring = start_ring
    case Dict.fetch(services, service) do
      {:ok, nodes} ->
        :ok = Discovery.Ring.add(pid, Set.to_list(nodes))
      :error ->
        :ok
    end
    {:noreply, %{state | rings: Dict.put(rings, service, new_ring)}}
  end

  #
  # Private
  #

  defp _drop(node, %{services: services} = state) do
    _drop(node, Dict.keys(services), state)
  end

  defp _drop(_, [], state), do: state
  defp _drop(node, [service|rest], state) do
    new_state = drop_service(state, service, node) |> drop_ring(service, node) |> drop_node(node)
    _drop(node, rest, new_state)
  end

  defp drop_node(%{nodes: nodes} = state, node) do
    case Dict.get(nodes, node) do
      nil ->
        state
      services ->
        case Set.size(services) do
          0 ->
            %{state | nodes: Dict.delete(nodes, node)}
          _ ->
            state
        end
    end
  end

  defp drop_service(%{services: services, nodes: nodes} = state, service, node) do
    state = case Dict.get(services, service) do
      nil ->
        state
      nodes ->
        new_nodes = Set.delete(nodes, node)
        case Set.size(new_nodes) do
          0 ->
            %{state | services: Dict.delete(services, service)}
          _ ->
            %{state | services: Dict.put(services, service, new_nodes)}
        end
    end

    case Dict.get(nodes, node) do
      nil ->
        state
      services ->
        %{state | nodes: Dict.put(nodes, node, Set.delete(services, service))}
    end
  end

  defp drop_ring(%{rings: rings, services: services} = state, service, node) do
    case Dict.get(rings, service) do
      nil ->
        state
      %Discovery.Ring{pid: pid} = ring ->
        Discovery.Ring.drop(pid, node)
        case Dict.get(services, service) do
          nil ->
            stop_ring(ring)
            %{state | rings: Dict.delete(rings, service)}
          _ ->
            state
        end
    end
  end
end
