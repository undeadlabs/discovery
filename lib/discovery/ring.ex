defmodule Discovery.Ring do
  use GenServer
  @name Discovery.Ring

  def start_link do
    GenServer.start_link(__MODULE__, :ok, name: @name)
  end

  def add(service, node) when is_atom(node), do: add(service, to_string(node))
  def add(service, node) when is_binary(node), do: GenServer.call(@name, {:add, service, node})

  def create(ring) when is_atom(ring), do: to_string(ring) |> create
  def create(ring) when is_binary(ring), do: GenServer.call(@name, {:create, ring})

  def destroy(ring) when is_atom(ring), do: to_string(ring) |> destroy
  def destroy(ring) when is_binary(ring), do: GenServer.call(@name, {:destroy, ring})

  def drop(service, node) when is_atom(node), do: drop(service, to_string(node))
  def drop(service, node) when is_list(service) or is_binary(service) and is_binary(node) do
    GenServer.call(@name, {:drop, service, node})
  end

  def find(service, hash) when is_atom(hash), do: find(service, to_string(hash))
  def find(service, hash) when is_binary(hash), do: GenServer.call(@name, {:find, service, hash})

  #
  # Private API
  #

  defp remove_node([]), do: :ok
  defp remove_node([ring|rest], node) do
    :ok = :hash_ring.remove_node(ring, node)
    remove_node(rest, node)
  end
  defp remove_node(ring, node) do
    :ok = :hash_ring.remove_node(ring, node)
  end

  #
  # GenServer callbacks
  #

  def init(:ok) do
    {:ok, _} = :hash_ring.start_link
    replicas = Application.get_env(:discovery, :replica_count, 128)
    {:ok, %{replicas: replicas}, 0}
  end

  def handle_info(:timeout, %{replicas: replicas} = state) do
    Enum.each(Discovery.Directory.services, fn({service, nodes}) ->
      :ok = :hash_ring.create_ring(service, replicas)
      Enum.each(nodes, fn(node) ->
        :ok = :hash_ring.add_node(service, to_string(node))
      end)
    end)

    {:noreply, state}
  end

  def handle_call({:add, ring, node}, _, %{replicas: replicas} = state) do
    case :hash_ring.add_node(ring, node) do
      {:error, :ring_not_found} ->
        :ok = :hash_ring.create_ring(ring, replicas)
        {:reply, :hash_ring.add_node(ring, node), state}
      _ ->
        {:reply, :hash_ring.add_node(ring, node), state}
    end
  end

  def handle_call({:create, name}, _, %{replicas: replicas} = state) do
    {:reply, :hash_ring.create_ring(name, replicas), state}
  end

  def handle_call({:destroy, name}, _, state) do
    {:reply, :hash_ring.delete_ring(name), state}
  end

  def handle_call({:drop, ring, node}, _, state) do
    {:reply, remove_node(ring, node), state}
  end

  def handle_call({:find, ring, key}, _, state) do
    case :hash_ring.find_node(ring, key) do
      {:ok, node} ->
        result = {:ok, String.to_atom(node)}
      error ->
        result = error
    end

    {:reply, result, ring}
  end

  def terminate(_, ring) do
    :hash_ring.stop
    :ok
  end
end
