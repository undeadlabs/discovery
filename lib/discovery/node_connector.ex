defmodule Discovery.NodeConnector do
  use GenServer
  @name :node_connector

  def start_link do
    GenServer.start_link(__MODULE__, [], name: @name)
  end

  def connect(node) when is_atom(node) do
    GenServer.call(@name, {:connect, node})
  end

  def disconnect(node) when is_atom(node) do
    GenServer.call(@name, {:disconnect, node})
  end

  #
  # Private
  #

  defp attempt_connect(node, retry_ms) do
    case Node.connect(node) do
      false ->
        timer = :erlang.send_after(retry_ms, self, {:retry_connect, node})
        {:error, timer}
      result ->
        result
    end
  end

  #
  # GenServer callbacks
  #

  def init([]) do
    {:ok, %{retry_ms: Application.get_env(:discovery, :retry_connect_ms), timers: %{}}}
  end

  def handle_call({:connect, node}, _from, %{retry_ms: retry_ms, timers: timers} = state) do
    case attempt_connect(node, retry_ms) do
      {:error, timer} ->
        new_timers = Dict.put(timers, node, timer)
        {:reply, :retrying, %{state | timers: new_timers}}
      result ->
        {:reply, result, state}
    end
  end

  def handle_call({:disconnect, node}, _from, %{timers: timers} = state) do
    case Dict.fetch(timers, node) do
      {:ok, timer} ->
        :erlang.cancel_timer(timer)
      _ ->
        :ok
    end

    {:reply, Node.disconnect(node), state}
  end

  def handle_info({:retry_connect, node}, %{timers: timers, retry_ms: retry_ms} = state) do
    case attempt_connect(node, retry_ms) do
      {:error, timer} ->
        new_timers = Dict.put(timers, node, timer)
      _ ->
        new_timers = Dict.delete(timers, node)
    end

    {:noreply, %{state | timers: new_timers}}
  end
end
