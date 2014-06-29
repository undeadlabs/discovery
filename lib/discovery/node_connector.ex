Code.ensure_compiled(Discovery.Service)

defmodule Discovery.NodeConnector do
  use GenServer
  alias Discovery.Directory

  @name Discovery.NodeConnector

  def start_link do
    GenServer.start_link(__MODULE__, [], name: @name)
  end

  def connect(node, service) when is_atom(node) and is_binary(service) do
    GenServer.call(@name, {:connect, node, service})
  end

  def disconnect(node) when is_atom(node) do
    GenServer.call(@name, {:disconnect, node})
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

  defp attempt_disconnect(node, %{timers: timers, nodes: nodes, services: services} = state) do
    case Dict.pop(timers, node) do
      {nil, new_timers} ->
        new_timers = new_timers
      {timer, new_timers} ->
        :erlang.cancel_timer(timer)
        new_timers = new_timers
    end

    case Dict.pop(nodes, node) do
      {nil, new_nodes} ->
        new_nodes = new_nodes
      {service, new_nodes} ->
        new_nodes    = new_nodes
        new_services = :sets.del_element(service, services)

        if new_services |> :sets.to_list |> Enum.empty? do
          new_services = Dict.delete(services, service)
        end
    end

    Node.monitor(node, false)
    Node.disconnect(node)

    %{state | nodes: new_nodes, timers: new_timers, services: new_services}
  end

  #
  # GenServer callbacks
  #

  def init([]) do
    nodes    = %{} # Discovery.Directory.nodes
    services = %{} # Discovery.Directory.services
    retry_ms = Application.get_env(:discovery, :retry_connect_ms, 5000)

    {:ok, %{retry_ms: retry_ms, timers: %{}, nodes: nodes, services: services}}
  end

  def handle_call({:connect, node, service}, _from, %{nodes: nodes, services: services} = state) do
    case Dict.fetch(nodes, node) do
      {:ok, nil} ->
        case Dict.fetch(services, service) do
          {:ok, nil} ->
            new_services = Dict.put(services, service, :sets.from_list([node]))
          {:ok, nodes} ->
            new_services = Dict.put(services, service, :sets.add_element(node, nodes))
        end

        new_nodes = Dict.put(nodes, node, service)
        new_state = attempt_connect(node, %{state | nodes: new_nodes, services: new_services})
        {:reply, :ok, new_state}
      {:ok, _} ->
        {:reply, :ok, state}
    end
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
