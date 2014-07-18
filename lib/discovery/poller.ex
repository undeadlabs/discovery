#
# The MIT License (MIT)
#
# Copyright (c) 2014 Undead Labs, LLC
#

defmodule Discovery.Poller do
  @moduledoc """
  Notifies subscribers of node availability within Consul for a particular service.
  """

  use GenServer
  import Consul.Response, only: [consul_index: 1]

  @type handler :: atom | {atom, list} | (([Discovery.Service.t]) -> any)

  @retry_ms 5000

  @spec start_link(binary) :: GenServer.on_start
  def start_link(service) when is_binary(service) do
    GenServer.start_link(__MODULE__, [service])
  end

  @spec start_link(binary, handler | [handler]) :: GenServer.on_start
  def start_link(service, handlers) when is_binary(service) and is_list(handlers) do
    GenServer.start_link(__MODULE__, [service, handlers])
  end
  def start_link(service, handler) when is_binary(service) and is_atom(handler) do
    GenServer.start_link(__MODULE__, [service, [handler]])
  end

  @spec async_poll(binary | integer, binary) :: Task.t
  def async_poll(index, service) do
    Task.async(__MODULE__, :poll, [index, service])
  end

  @spec add_handler(pid, handler) :: :ok
  def add_handler(poller, handler, args \\ []) when is_pid(poller) do
    GenServer.call(poller, {:add_handler, handler, args})
  end

  @spec poll(binary | integer, binary) :: {:ok | :error, HTTPoison.Response.t | binary}
  def poll(index, service) do
    Consul.Health.service(index, service)
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

  def init([service, handlers]) do
    {:ok, em} = GenEvent.start_link

    Enum.each(handlers, fn
      {module, args} ->
        :ok = GenEvent.add_handler(em, module, args)
      fun when is_function(fun, 1) ->
        :ok = GenEvent.add_handler(em, Discovery.Handler.Generic, [fun])
      module ->
        :ok = GenEvent.add_handler(em, module, [])
    end)

    {:ok, %{em: em, service: service, services: [], index: nil, task: nil}, 0}
  end

  def init([service]) do
    init([service, []])
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
        case Discovery.Service.from_health(body) do
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

  def handle_call({:add_handler, module, args}, _from, %{em: em, services: services} = state) do
    :ok = GenEvent.add_handler(em, module, args)
    {:reply, GenEvent.sync_notify(em, {:services, services}), state}
  end
end
