defmodule Discovery.HeartbeatTest do
  use ExUnit.Case

  test "starting a heartbeat process registers the service with discovery" do
    refute Enum.member?(Discovery.apps, "test_service")
    {:ok, pid} = Discovery.Heartbeat.start("service:test_service", (15 * 1000))
    assert Enum.member?(Discovery.apps, "test_service")
    Discovery.Heartbeat.stop(pid)
  end
end
