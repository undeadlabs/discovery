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
  @spec add(atom, binary) :: :ok
  def add(node, service) when is_atom(node) and is_binary(service) do
    GenServer.call(@name, {:add, node, service})
  end

  @doc false
  def clear do
    GenServer.call(@name, :clear)
  end

  @doc """
  Drop a node from the directory.
  """
  @spec drop(atom) :: :ok
  def drop(node) when is_atom(node) do
    GenServer.call(@name, {:drop, node})
  end

  @doc """
  Find a node running service hashed by hash.
  """
  @spec find(binary, binary) :: {:ok, node} | {:error, term}
  def find(service, hash) do
    GenServer.call(@name, {:find, service, hash})
  end

  @doc """
  Checks if node exists within the Directory.
  """
  @spec has_node?(atom) :: boolean
  def has_node?(node) when is_atom(node) do
    GenServer.call(@name, {:has_node?, node})
  end

  @doc """
  List all nodes and the services they provide.
  """
  @spec nodes :: Set.t
  def nodes do
    GenServer.call(@name, :nodes)
  end

  @doc """
  List all nodes which provide the given service.
  """
  @spec nodes(binary) :: list
  def nodes(service) when is_binary(service) do
    GenServer.call(@name, {:nodes, service})
  end

  @doc """
  List all services and the nodes which provide them.
  """
  @spec services :: Set.t
  def services do
    GenServer.call(@name, :services)
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
    :ok = Discovery.Ring.stop(pid)
  end

  #
  # GenServer callbacks
  #

  def init(:ok) do
    {:ok, %{nodes: %{}, services: %{}, rings: %{}}}
  end

  def handle_call({:add, node, service}, _, %{nodes: nodes, services: services, rings: rings} = state) do
    case Dict.fetch(rings, service) do
      {:ok, ring} ->
        ring = ring
      :error ->
        ring = start_ring
    end

    :ok = Discovery.Ring.add(ring.pid, node)

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

    {:reply, :ok, %{state | nodes: new_nodes, services: new_services, rings: Dict.put(rings, service, ring)}}
  end

  def handle_call(:clear, _, %{nodes: nodes, rings: rings}) do
    Map.keys(nodes) |> Enum.each(&Discovery.Ring.drop/1)
    Enum.each(rings, fn({_, ring}) -> stop_ring(ring) end)
    {:reply, :ok, %{nodes: %{}, services: %{}, rings: %{}}}
  end

  def handle_call({:drop, node}, _, %{nodes: nodes, services: services, rings: rings} = state) do
    case Dict.pop(nodes, node) do
      {nil, new_nodes} ->
        new_nodes    = new_nodes
        new_services = services
        new_rings    = rings
      {_, new_nodes} ->
        new_nodes                 = new_nodes
        {new_services, new_rings} = Enum.reduce(services, {%{}, %{}}, fn({key, value}, {services, rings} = acc) ->
          new_set = Set.delete(value, node)
          case Enum.empty?(new_set) do
            true ->
              case Dict.fetch(rings, key) do
                {:ok, %Discovery.Ring{pid: pid}} ->
                  Discovery.Ring.drop(pid, node)
                :error ->
                  :ok
              end
              acc
            false ->
              case Dict.pop(rings, key) do
                {nil, new_rings} ->
                  new_rings = new_rings
                {ring, new_rings} ->
                  stop_ring(ring)
                  new_rings = new_rings
              end
              {Dict.put(services, key, new_set), new_rings}
          end
        end)
    end

    {:reply, :ok, %{state | nodes: new_nodes, services: new_services, rings: new_rings}}
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
end
