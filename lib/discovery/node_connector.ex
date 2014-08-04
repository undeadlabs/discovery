#
# The MIT License (MIT)
#
# Copyright (c) 2014 Undead Labs, LLC
#

defmodule Discovery.NodeConnector do
  @moduledoc """
  Connects to and monitors connections to nodes. The connection will be retried until it
  is established or it is explicitly disconnected by calling `NodeConnector.disconnect/1`.
  """

  use GenServer
  alias Discovery.Directory

  @name Discovery.NodeConnector

  def start_link do
    GenServer.start_link(__MODULE__, [], name: @name)
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

  #
  # Private
  #

  defp attempt_connect(node, %{retry_ms: retry_ms, timers: timers} = state) do
    case Node.connect(node) do
      result when result in [false, :ignored] ->
        timer      = :erlang.send_after(retry_ms, self, {:retry_connect, node})
        new_timers = Dict.put(timers, node, timer)
      true ->
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
    end

    %{state | timers: new_timers}
  end

  defp attempt_disconnect(node, %{timers: timers} = state) do
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

    %{state | timers: new_timers}
  end

  #
  # GenServer callbacks
  #

  def init([]) do
    retry_ms = Application.get_env(:discovery, :retry_connect_ms, 5000)
    {:ok, %{retry_ms: retry_ms, timers: %{}}}
  end

  def handle_call({:connect, node, service}, _from, state) do
    case Directory.has_node?(node) do
      true ->
        {:reply, :ok, state}
      false ->
        :ok       = Directory.add(node, service)
        new_state = attempt_connect(node, state)
        {:reply, :ok, new_state}
    end
  end

  def handle_call({:disconnect, node, services}, _from, state) do
    :ok = Directory.drop(node, services)
    case Directory.has_node?(node) do
      true ->
        {:reply, :ok, state}
      false ->
        new_state = attempt_disconnect(node, state)
        {:reply, :ok, new_state}
    end
  end

  def handle_info({:retry_connect, node}, state) do
    new_state = attempt_connect(node, state)
    {:noreply, new_state}
  end

  def handle_info({:nodedown, node}, state) do
    case Directory.has_node?(node) do
      true ->
        new_state = attempt_connect(node, state)
        {:noreply, new_state}
      false ->
        {:noreply, state}
    end
  end
end
