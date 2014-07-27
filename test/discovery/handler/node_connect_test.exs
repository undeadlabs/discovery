defmodule Discovery.Handler.NodeConnectTest do
  use ExUnit.Case
  alias Discovery.Handler.NodeConnect
  alias Discovery.Directory
  alias Discovery.Service

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
end
