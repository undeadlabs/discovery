defmodule Discovery.Poller do
  @moduledoc """
  Notifies subscribers of node availability within Consul for a particular service.
  """

  use GenServer
  import Consul.Response, only: [consul_index: 1]

  @retry_ms 5000

  def start_link(service) when is_binary(service) do
    GenServer.start_link(__MODULE__, [service])
  end

  @spec async_poll(pid, binary | integer, binary) :: Task.t
  def async_poll(poller, index, service) do
    Task.async(__MODULE__, :poll, [poller, index, service])
  end

  @spec poll(pid, binary | integer, binary) :: :ok
  def poll(poller, index, service) do
    Consul.Catalog.service(index, service)
  end

  @spec subscribe(pid, atom, pid) :: :ok
  def subscribe(poller, module, subscriber) when is_pid(poller) and is_atom(module) and is_pid(subscriber) do
    GenServer.call(poller, {:subscribe, module, subscriber})
  end

  @spec unsubscribe(pid, atom, pid) :: :ok
  def unsubscribe(poller, module, subscriber) when is_pid(poller) and is_atom(module) and is_pid(subscriber) do
    GenServer.call(poller, {:unsubscribe, module, subscriber})
  end

  #
  # Private
  #

  defp notify_change(nodes, %{nodes: nodes}), do: :ok
  defp notify_change(nodes, %{em: em}) do
    GenEvent.notify(em, {:nodes, nodes})
  end

  #
  # GenServer callbacks
  #

  def init([service]) do
    {:ok, em} = GenEvent.start_link
    {:ok, %{em: em, service: service, nodes: [], index: nil, task: nil}, 0}
  end

  # Seed node-service data and begin polling
  def handle_info(:timeout, %{service: service, index: nil} = state) do
    case Consul.Catalog.service(service) do
      {:ok, %{body: body} = response} ->
        case Discovery.Node.build(body) do
          [] = result ->
            new_nodes = result
          nodes ->
            new_nodes = nodes
        end
        :ok       = notify_change(new_nodes, state)
        new_state = %{state | nodes: new_nodes, index: consul_index(response)}
        task      = async_poll(self, new_state.index, service)
        {:noreply, %{new_state | task: task}}
      {:error, _} ->
        {:noreply, state, @retry_ms}
    end
  end

  # Handle results from polling task
  def handle_info({ref, results}, %{task: %Task{ref: ref}} = state) do
    case results do
      {:ok, %{body: body} = response} ->
        case Discovery.Node.build(body) do
          [] = result ->
            new_nodes = result
          nodes ->
            new_nodes = nodes
        end
        :ok       = notify_change(new_nodes, state)
        new_state = %{state | nodes: new_nodes, index: consul_index(response)}
        {:noreply, new_state}
      {:error, _} ->
        new_state = %{state | index: nil}
        {:noreply, new_state, @retry_ms}
    end
  end

  # Poller completed
  def handle_info({:DOWN, ref, _, _, :normal}, %{service: service, index: index, task: %Task{ref: ref}} = state) do
    {:noreply, %{state | task: async_poll(self, index, service)}}
  end

  # Poller crashed
  def handle_info({:DOWN, ref, _, _, _}, %{task: %Task{ref: ref}} = state) do
    {:noreply, %{state | task: nil, index: nil}, @retry_ms}
  end

  def handle_call({:subscribe, module, subscriber}, _from, %{em: em, nodes: nodes} = state) do
    :ok = GenEvent.add_handler(em, {module, subscriber}, [], link: true)
    {:reply, GenEvent.notify(em, {:nodes, nodes}), state}
  end

  def handle_call({:unsubscribe, module, subscriber}, _from, %{em: em} = state) do
    {:reply, GenEvent.remove_handler(em, {module, subscriber}, []), state}
  end
end
