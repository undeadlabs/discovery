defmodule Discovery.Heartbeat do
  use GenServer

  @retry_ms 5000

  def start_link(check_id, interval) do
    GenServer.start_link(__MODULE__, [check_id, interval])
  end

  def send_pulse(check_id) do
    {result, _} = Consul.Agent.Check.pass(check_id)
    result
  end

  #
  # GenServer callbacks
  #

  def init([check_id, interval]) do
    {:ok, %{timer: nil, check_id: check_id, interval: interval}, 0}
  end

  def handle_info(:timeout, %{check_id: check_id, interval: interval} = state) do
    case send_pulse(check_id) do
      :ok ->
        timer = :erlang.send_after(interval, self, :pulse)
        {:noreply, %{state | timer: timer}}
      :error ->
        {:noreply, state, @retry_ms}
    end
  end

  def handle_info(:pulse, %{check_id: check_id, interval: interval, timer: timer} = state) do
    :erlang.cancel_timer(timer)
    send_pulse(check_id)
    new_timer = :erlang.send_after(interval, self, :pulse)
    {:noreply, %{state | timer: new_timer}}
  end
end
