defmodule Discovery.Ring do
  @moduledoc """
  Manages consistent hash rings of Erlang nodes for discovered services.
  """

  use GenServer
  @name Discovery.Ring

  def start_link do
    GenServer.start_link(__MODULE__, :ok, name: @name)
  end

  @doc """
  Add a node to the service ring.

  If no service ring exists for the given service one will be created.
  """
  @spec add(binary | atom, binary) :: :ok | {:error, term}
  def add(service, node) when is_atom(node), do: add(service, to_string(node))
  def add(service, node) when is_binary(node), do: GenServer.call(@name, {:add, service, node})

  @doc """
  Create a new hash ring for service.
  """
  @spec create(binary | atom) :: :ok | {:error, term}
  def create(service) when is_atom(service), do: to_string(service) |> create
  def create(service) when is_binary(service), do: GenServer.call(@name, {:create, service})

  @doc """
  Destroy a hash ring for service.
  """
  @spec destroy(binary | atom) :: :ok | {:error, term}
  def destroy(service) when is_atom(service), do: to_string(service) |> destroy
  def destroy(service) when is_binary(service), do: GenServer.call(@name, {:destroy, service})

  @doc """
  Drop a node from a service ring.
  """
  @spec drop(binary | list, binary | atom) :: :ok | {:error, term}
  def drop(service, node) when is_atom(node), do: drop(service, to_string(node))
  def drop(service, node) when is_list(service) or is_binary(service) and is_binary(node) do
    GenServer.call(@name, {:drop, service, node})
  end

  @doc """
  Find a node in a service ring with the given hash key.
  """
  @spec find(binary | atom, binary) :: {:ok, binary} | {:error, term}
  def find(service, hash) when is_atom(hash), do: find(service, to_string(hash))
  def find(service, hash) when is_binary(hash), do: GenServer.call(@name, {:find, service, hash})

  #
  # Private API
  #

  defp remove_node([], _), do: :ok
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

    {:reply, result, state}
  end

  def terminate(_, _) do
    :hash_ring.stop
    :ok
  end
end
