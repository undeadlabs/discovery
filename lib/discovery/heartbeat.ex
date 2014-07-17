#
# The MIT License (MIT)
#
# Copyright (c) 2014 Undead Labs, LLC
#

defmodule Discovery.Heartbeat do
  use GenServer

  @retry_ms 5000

  @spec start_link(binary, integer) :: GenServer.on_start
  def start_link(check_id, interval) do
    GenServer.start_link(__MODULE__, [check_id, interval])
  end

  #
  # Private API
  #

  defp send_pulse(check_id) do
    {result, _} = Consul.Agent.Check.pass(check_id)
    result
  end

  defp service_name(check_id) when is_binary(check_id) do
    case String.split(check_id, ":", parts: 2) do
      ["service", name] ->
        {:ok, name}
      _ ->
        {:error, :invalid_check_id}
    end
  end

  #
  # GenServer callbacks
  #

  def init([check_id, interval]) do
    case service_name(check_id) do
      {:ok, service} ->
        :ok = Discovery.Directory.add(Node.self, service)
        {:ok, %{timer: nil, check_id: check_id, interval: interval, service: service}, 0}
      error ->
        {:stop, error}
    end
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

  def terminate(_, %{service: service}) do
    Discovery.Directory.drop(Node.self, service)
    :ok
  end
end
