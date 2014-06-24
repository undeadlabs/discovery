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

  defp attempt_connect(node, %{retry_ms: retry_ms, nodes: nodes} = state) do
    case Node.connect(node) do
      result when result in [false, :ignored] ->
        timer     = :erlang.send_after(retry_ms, self, {:retry_connect, node})
        new_nodes = Dict.put(nodes, node, timer)
      true ->
        case Dict.fetch(nodes, node) do
          {:ok, nil} ->
            :ok
          :error ->
            Node.monitor(node, true)
          {:ok, timer} ->
            Node.monitor(node, true)
            :erlang.cancel_timer(timer)
        end
        new_nodes = Dict.put(nodes, node, nil)
    end

    %{state | nodes: new_nodes}
  end

  defp attempt_disconnect(node, %{nodes: nodes} = state) do
    case Dict.pop(nodes, node) do
      {nil, new_nodes} ->
        new_nodes = new_nodes
      {timer, new_nodes} ->
        :erlang.cancel_timer(timer)
        new_nodes = new_nodes
    end

    Node.monitor(node, false)
    Node.disconnect(node)

    %{state | nodes: new_nodes}
  end

  #
  # GenServer callbacks
  #

  def init([]) do
    {:ok, %{retry_ms: Application.get_env(:discovery, :retry_connect_ms), nodes: %{}}}
  end

  def handle_call({:connect, node}, _from, state) do
    new_state = attempt_connect(node, state)
    {:reply, :ok, new_state}
  end

  def handle_call({:disconnect, node}, _from, state) do
    new_state = attempt_disconnect(node, state)
    {:reply, :ok, new_state}
  end

  def handle_info({:retry_connect, node}, state) do
    new_state = attempt_connect(node, state)
    {:noreply, new_state}
  end

  def handle_info({:nodedown, node}, %{nodes: nodes} = state) do
    case Dict.fetch(nodes, node) do
      {:ok, _} ->
        new_state = attempt_connect(node, state)
        {:noreply, new_state}
      :error ->
        {:noreply, state}
    end
  end
end
