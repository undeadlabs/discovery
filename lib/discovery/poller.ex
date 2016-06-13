#
# The MIT License (MIT)
#
# Copyright (c) 2014-2015 Undead Labs, LLC
#

defmodule Discovery.Poller do
  @moduledoc """
  Notifies subscribers of node availability within Consul for a particular service.
  """

  require Logger
  use GenServer
  import Consul.Response, only: [consul_index: 1]

  @type handler :: atom | {atom, list} | (([Discovery.Service.t]) -> any)

  @wait     "10m"
  @retry_ms 30 * 1000

  @spec start_link(binary) :: GenServer.on_start
  def start_link(service) when is_binary(service) do
    GenServer.start_link(__MODULE__, [service])
  end

  @spec start_link(binary, handler | [handler]) :: GenServer.on_start
  def start_link(service, handlers) when is_binary(service) and is_list(handlers) do
    GenServer.start_link(__MODULE__, [service, handlers])
  end
  def start_link(service, handler) when is_binary(service) do
    GenServer.start_link(__MODULE__, [service, [handler]])
  end

  @spec async_poll(binary | integer, binary) :: Task.t
  def async_poll(index, service) do
    Task.async(__MODULE__, :poll, [index, service])
  end

  @spec add_handler(pid, atom) :: :ok
  def add_handler(poller, handler, args \\ []) when is_pid(poller) and is_atom(handler) do
    GenServer.call(poller, {:add_handler, handler, args})
  end

  @spec enabled? :: boolean
  def enabled? do
    Application.get_env(:discovery, :enable_polling, true)
  end

  @spec poll(binary | integer, binary | atom) :: {:ok | :error, HTTPoison.Response.t | binary}
  def poll(index, service) do
    Consul.Health.service(service, index: index, wait: @wait)
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

    registered_handlers = Enum.map handlers, fn
      {module, args} ->
        handler = {module, make_ref()}
        :ok     = GenEvent.add_mon_handler(em, handler, args)
        {handler, args}
      fun when is_function(fun, 1) ->
        handler = {Discovery.Handler.Generic, make_ref}
        args    = [fun]
        :ok     = GenEvent.add_mon_handler(em, handler, args)
        {handler, args}
      module ->
        handler = {module, make_ref()}
        args    = []
        :ok     = GenEvent.add_mon_handler(em, handler, args)
        {handler, args}
    end

    handler_map = Enum.into registered_handlers, HashDict.new

    {:ok, %{em: em, service: service, services: [], index: nil, task: nil, handlers: handler_map}, 0}
  end

  def init([service]) do
    init([service, []])
  end

  # Seed node-service data and begin polling
  def handle_info(:timeout, %{service: service, index: nil} = state) do
    # determine if we provide the service and notify listeners
    if Discovery.Util.app_running?(service) do
      %Discovery.Service{name: service, tags: [otp_name: Node.self], status: "passing"}
        |> notify_change(state)
    end

    if enabled? do
      case Consul.Health.service(service) do
        {:ok, %{body: body} = response} ->
          new_services =
          case Discovery.Service.from_health(body) do
            [] = result -> result
            services -> services
          end
          :ok       = notify_change(new_services, state)
          new_state = %{state | services: new_services, index: consul_index(response)}
          task      = async_poll(new_state.index, service)
          {:noreply, %{new_state | task: task}}
        {:error, error} ->
          _ = Logger.warn "Error polling service status from Consul: #{inspect error}"
          {:noreply, state, @retry_ms}
      end
    else
      {:noreply, state}
    end
  end

  # Handle results from polling task
  def handle_info({ref, results}, %{task: %Task{ref: ref}} = state) do
    case results do
      {:ok, %{body: body} = response} ->
        new_services =
        case Discovery.Service.from_health(body) do
          [] = result -> result
          services -> services
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

  def handle_info({:gen_event_EXIT, _, :normal}, state) do
    {:noreply, state}
  end
  def handle_info({:gen_event_EXIT, _, {:swapped, _, _}}, state) do
    {:noreply, state}
  end
  def handle_info({:gen_event_EXIT, _, :shutdown}, state) do
    {:noreply, state}
  end
  def handle_info({:gen_event_EXIT, handler, _}, %{em: em, handlers: handlers} = state) do
    args = HashDict.get(handlers, handler)
    :ok  = GenEvent.add_mon_handler(em, handler, args)
    {:noreply, state}
  end

  def handle_call({:add_handler, module, args}, _from, %{em: em, services: services, handlers: handlers} = state) do
    handler   = {module, make_ref()}
    :ok       = GenEvent.add_mon_handler(em, handler, args)
    new_state = %{state | handlers: HashDict.put(handlers, handler, args)}
    reply     = GenEvent.sync_notify(em, {:services, services})
    {:reply, reply, new_state}
  end
end
