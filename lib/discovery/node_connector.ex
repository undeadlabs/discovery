#
# The MIT License (MIT)
#
# Copyright (c) 2014-2015 Undead Labs, LLC
#

defmodule Discovery.NodeConnector do
  @moduledoc """
  Connects to and monitors connections to nodes. The connection will be retried until it
  is established or it is explicitly disconnected by calling `NodeConnector.disconnect/1`.
  """

  require Logger

  use GenServer
  alias Discovery.Directory
  alias Discovery.NodeConnector

  @name __MODULE__

  @spec start_link :: GenServer.on_start
  def start_link do
    GenServer.start_link(__MODULE__, [], name: @name)
  end

  @spec start_link([atom] | [{atom, list}]) :: GenServer.on_start
  def start_link(handlers) do
    GenServer.start_link(__MODULE__, handlers, name: @name)
  end

  @doc """
  Register a `NodeConnector.Handler` to be invoked on successful node connect and disconnect.
  """
  @spec add_handler(atom, list) :: {:ok, {atom, reference}} | {:error, term}
  def add_handler(module, args \\ []) do
    GenServer.call(@name, {:add_handler, module, args})
  end

  @doc """
  Register the given node with the `Discovery.Directory` for providing the given
  service and attempt to connect to the node if not already connected.
  """
  @spec connect(atom | binary, binary) :: :ok
  def connect(node, service) when is_binary(node), do: connect(String.to_atom(node), service)
  def connect(node, service) when is_atom(node) and is_binary(service) do
    GenServer.call(@name, {:connect, node, service})
  end

  @doc """
  Deregister the given node with the `Discovery.Directory` for providing the given
  service and attempt to disconnect from the node if it is no longer providing any services.
  """
  @spec disconnect(atom | binary, binary) :: :ok
  def disconnect(node, services) when is_binary(node), do: disconnect(String.to_atom(node), services)
  def disconnect(node, services) when is_atom(node) do
    GenServer.call(@name, {:disconnect, node, services})
  end

  @doc """
  Remove a registered `NodeConnector.Handler`.
  """
  @spec remove_handler(atom, reference) :: term | {:error, term}
  def remove_handler(module, ref) do
    GenServer.call(@name, {:remove_handler, module, ref})
  end

  #
  # Private
  #

  defp attempt_connect(node, %{em: em, retry_ms: retry_ms, timers: timers} = state) do
    if node == Node.self do
      NodeConnector.Handler.notify_connect(em, node)
      state
    else
      Logger.debug "Attempting to connect to node: #{node}"
      case Node.connect(node) do
        result when result in [false, :ignored] ->
          timer      = :erlang.send_after(retry_ms, self, {:retry_connect, node})
          new_timers = Dict.put(timers, node, timer)
        true ->
          Logger.info "Connected to: #{node}"
          NodeConnector.Handler.notify_connect(em, node)
          case Directory.add(node, Node.self, Discovery.apps) do
            :ok ->
              case Dict.fetch(timers, node) do
                {:ok, nil} ->
                  :ok
                :error ->
                  Node.monitor(node, true)
                {:ok, timer} ->
                  Node.monitor(node, true)
                  :erlang.cancel_timer(timer)
              end
              new_timers = Dict.put(timers, node, nil)
            {:error, _} ->
              timer      = :erlang.send_after(retry_ms, self, {:retry_connect, node})
              new_timers = Dict.put(timers, node, timer)
          end
      end

      %{state | timers: new_timers}
    end
  end

  defp attempt_disconnect(node, %{em: em, timers: timers} = state) do
    Logger.debug "Attempting to disconnect from node: #{node}"
    case Dict.pop(timers, node) do
      {nil, new_timers} ->
        new_timers = new_timers
      {timer, new_timers} ->
        :erlang.cancel_timer(timer)
        new_timers = new_timers
    end

    try do
      Node.monitor(node, false)
    rescue
      _ in ArgumentError -> :ok
    end

    Node.disconnect(node)
    Logger.info "Disconnected from: #{node}"
    NodeConnector.Handler.notify_disconnect(em, node)

    %{state | timers: new_timers}
  end

  defp register_handler(em, module, args \\ []) do
    ref = make_ref()
    case GenEvent.add_handler(em, {module, ref}, args) do
      :ok   -> {:ok, ref}
      error -> error
    end
  end

  defp unregister_handler(em, module, ref) do
    GenEvent.remove_handler(em, {module, ref}, [])
  end

  #
  # GenServer callbacks
  #

  def init(handlers) do
    retry_ms  = Application.get_env(:discovery, :retry_connect_ms, 5000)
    {:ok, em} = GenEvent.start_link
    Enum.each handlers, fn
      {module, args} ->
        register_handler(em, module, args)
      module when is_atom(module) ->
        register_handler(em, module)
    end
    {:ok, %{retry_ms: retry_ms, timers: %{}, em: em}}
  end

  def handle_call({:add_handler, module, args}, _, %{em: em} = state) do
    case register_handler(em, module, args) do
      {:ok, ref} ->
        {:reply, {:ok, {module, ref}}, state}
      error ->
        {:reply, error, state}
    end
  end

  def handle_call({:connect, node, service}, _, state) do
    :ok       = Directory.add(node, service)
    new_state = attempt_connect(node, state)
    {:reply, :ok, new_state}
  end

  def handle_call({:disconnect, node, services}, _, state) do
    :ok = Directory.drop(node, services)
    case Directory.has_node?(node) do
      true ->
        {:reply, :ok, state}
      false ->
        new_state = attempt_disconnect(node, state)
        {:reply, :ok, new_state}
    end
  end

  def handle_call({:remove_handler, module, ref}, _, %{em: em} = state) do
    {:reply, unregister_handler(em, module, ref), state}
  end

  def handle_info({:retry_connect, node}, state) do
    new_state = attempt_connect(node, state)
    {:noreply, new_state}
  end

  def handle_info({:nodedown, node}, state) do
    Logger.warn "Unexpected disconnect from node: #{node}"
    case Directory.has_node?(node) do
      true ->
        new_state = attempt_connect(node, state)
        {:noreply, new_state}
      false ->
        {:noreply, state}
    end
  end
end
