defmodule Discovery.Handler.NodeConnectTest do
  use ExUnit.Case
  alias Discovery.Handler.NodeConnect
  alias Discovery.Directory
  alias Discovery.Service

  setup do
    on_exit fn ->
      Directory.clear
    end
  end

  test "stale/2" do
    Directory.add(:'reset@undead', "router")
    Directory.add(:'reset@undead', "account")
    Directory.add(:'reset-2@undead', "router")
    Directory.add(:'reset-3@undead', "router")
    Directory.add(:'reset-3@undead', "account")
    services = [
      %Service{name: "router", tags: [otp_name: "reset@undead"]},
      %Service{name: "router", tags: [otp_name: "reset-3@undead"]},
      %Service{name: "account", tags: [otp_name: "reset-3@undead"]},
    ]

    assert NodeConnect.stale(services) == [{"account", [:'reset@undead']}, {"router", [:'reset-2@undead']}]
  end

  test "connecting new nodes" do
    [
      %Service{name: "router", tags: [otp_name: "reset@undead"], status: "passing"},
      %Service{name: "account", tags: [otp_name: "reset-2@undead"], status: "critical"},
    ] |> NodeConnect.connect

    assert Directory.nodes |> Dict.has_key?(:reset@undead)
    refute Directory.nodes |> Dict.has_key?(:'reset-2@undead')
    assert Directory.nodes("router") == [:'reset@undead']
    assert Directory.nodes("account") == []
  end

  test "disconnecting from given service list" do
    Directory.add(:reset@undead, "router")
    Directory.add(:reset@undead, "account")
    Directory.add(:'reset-2@undead', "router")
    Directory.add(:'reset-3@undead', "account")
    diff = [
      %Service{name: "router", tags: [otp_name: "reset@undead"]},
      %Service{name: "account", tags: [otp_name: "reset-3@undead"]},
    ] |> NodeConnect.stale

    NodeConnect.disconnect(diff)

    assert Directory.nodes("router") == [:reset@undead]
    assert Directory.nodes("account") == [:'reset-3@undead']
  end
end
