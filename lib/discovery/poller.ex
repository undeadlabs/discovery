defmodule Discovery.Poller do
  @moduledoc """
  Notifies subscribers of node availability within Consul for a particular service.
  """

  use GenServer
  import Consul.Response, only: [consul_index: 1]

  def start_link(service) when is_binary(service) do
    GenServer.start_link(__MODULE__, [service])
  end

  @spec async_poll(pid, binary | integer, binary) :: Task.t
  def async_poll(poller, index, service) do
    Task.async(__MODULE__, :poll, [poller, index, service])
  end

  @spec poll(pid, binary | integer, binary) :: :ok
  def poll(poller, index, service) do
    results = Consul.Catalog.service(index, service)
    GenServer.call(poller, {:poll_response, results})
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
      {:error, response} ->
        new_state = %{state | nodes: [], index: consul_index(response)}
    end

    task = async_poll(self, new_state.index, service)

    {:noreply, %{new_state | task: task}}
  end

  def handle_info({:DOWN, ref, _, _, _}, %{service: service, index: index, task: %Task{ref: ref}} = state) do
    task = async_poll(self, index, service)
    {:noreply, %{state | task: task}}
  end

  def handle_call({:poll_response, results}, _from, %{service: service} = state) do
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
      {:error, response} ->
        new_state = %{state | nodes: [], index: consul_index(response)}
    end

    task = async_poll(self, new_state.index, service)

    {:reply, :ok, %{new_state | task: task}}
  end

  def handle_call({:subscribe, module, subscriber}, _from, %{em: em, nodes: nodes} = state) do
    :ok = GenEvent.add_handler(em, {module, subscriber}, [], link: true)
    {:reply, GenEvent.notify(em, {:nodes, nodes}), state}
  end

  def handle_call({:unsubscribe, module, subscriber}, _from, %{em: em} = state) do
    {:reply, GenEvent.remove_handler(em, {module, subscriber}, []), state}
  end
end
