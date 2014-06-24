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

  @spec async_poll(binary | integer, binary) :: Task.t
  def async_poll(index, service) do
    Task.async(__MODULE__, :poll, [index, service])
  end

  def add_handler(poller, module) when is_pid(poller) and is_atom(module) do
    GenServer.call(poller, {:add_handler, module})
  end

  @spec poll(binary | integer, binary) :: {:ok | :error, HTTPoison.Response.t | binary}
  def poll(index, service) do
    Consul.Health.service(index, service)
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

  defp notify_change(services, %{services: services}), do: :ok
  defp notify_change(services, %{em: em}) do
    GenEvent.sync_notify(em, {:services, services})
  end

  #
  # GenServer callbacks
  #

  def init([service]) do
    {:ok, em} = GenEvent.start_link
    {:ok, %{em: em, service: service, services: [], index: nil, task: nil}, 0}
  end

  # Seed node-service data and begin polling
  def handle_info(:timeout, %{service: service, index: nil} = state) do
    case Consul.Health.service(service) do
      {:ok, %{body: body} = response} ->
        case Discovery.Service.from_health(body) do
          [] = result ->
            new_services = result
          services ->
            new_services = services
        end
        :ok       = notify_change(new_services, state)
        new_state = %{state | services: new_services, index: consul_index(response)}
        task      = async_poll(new_state.index, service)
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
            new_services = result
          services ->
            new_services = services
        end
        :ok       = notify_change(new_services, state)
        new_state = %{state | services: new_services, index: consul_index(response)}
        {:noreply, new_state}
      {:error, _} ->
        new_state = %{state | index: nil}
        {:noreply, new_state, @retry_ms}
    end
  end

  # Poller completed
  def handle_info({:DOWN, ref, _, _, :normal}, %{service: service, index: index, task: %Task{ref: ref}} = state) do
    {:noreply, %{state | task: async_poll(index, service)}}
  end

  # Poller crashed
  def handle_info({:DOWN, ref, _, _, _}, %{task: %Task{ref: ref}} = state) do
    {:noreply, %{state | task: nil, index: nil}, @retry_ms}
  end

  def handle_call({:add_handler, module}, _from, %{em: em, services: services} = state) do
    :ok = GenEvent.add_handler(em, module, [])
    {:reply, GenEvent.sync_notify(em, {:services, services}), state}
  end

  def handle_call({:subscribe, module, subscriber}, _from, %{em: em, services: services} = state) do
    :ok = GenEvent.add_handler(em, {module, subscriber}, [], link: true)
    {:reply, GenEvent.sync_notify(em, {:services, services}), state}
  end

  def handle_call({:unsubscribe, module, subscriber}, _from, %{em: em} = state) do
    {:reply, GenEvent.remove_handler(em, {module, subscriber}, []), state}
  end
end
