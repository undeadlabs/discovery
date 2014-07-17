defmodule Discovery.ServiceTest do
  use ExUnit.Case
  alias Discovery.Service

  setup do
    checks = [
      %{
        "Node" => %{
          "Node" => "foobar",
          "Address" => "10.1.10.12"
        },
        "Service" => %{
          "ID" => "redis",
          "Service" => "redis",
          "Tags" => [
            "otp_name:route@jamie.undeadlabs.com"
          ],
          "Port" => 8000
        },
        "Checks" => [
          %{
            "Node" => "foobar",
            "CheckID" => "service:redis",
            "Name" => "Service 'redis' check",
            "Status" => "passing",
            "Notes" => "",
            "Output" => "",
            "ServiceID" => "redis",
            "ServiceName" => "redis"
          },
          %{
            "Node" => "foobar",
            "CheckID" => "serfHealth",
            "Name" => "Serf Health Status",
            "Status" => "passing",
            "Notes" => "",
            "Output" => "",
            "ServiceID" => "",
            "ServiceName" => ""
          }
        ]
      }
    ]

    {:ok, checks: checks}
  end

  test "extract structs from health", ctx do
    [service|_] = services = Service.from_health(ctx[:checks])
    assert Enum.count(services) == 1
    assert service.name == "redis"
    assert service.port == 8000
    assert service.status == "passing"
    assert service.tags == [otp_name: "route@jamie.undeadlabs.com"]
    assert service.node.name == "foobar"
    assert service.node.address == "10.1.10.12"
  end
end
