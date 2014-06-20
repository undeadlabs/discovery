defmodule Discovery.NodeTest do
  use ExUnit.Case
  doctest Discovery.Node

  test "build a list of new node structs from a consul response containing a list" do
    nodes = Discovery.Node.build([%{"Address" => "10.0.2.15", "Node" => "default-ubuntu-1204", "ServiceID" => "route",
      "ServiceName" => "route", "ServicePort" => 10100, "ServiceTags" => nil}])
    assert nodes == [%Discovery.Node{address: "10.0.2.15", node: "default-ubuntu-1204", service_id: "route",
      service_name: "route", service_port: 10100, service_tags: nil}]
  end

  test "build a new node struct from a consul response containing a single node" do
    nodes = Discovery.Node.build(%{"Address" => "10.0.2.15", "Node" => "default-ubuntu-1204", "ServiceID" => "route",
      "ServiceName" => "route", "ServicePort" => 10100, "ServiceTags" => nil})
    assert nodes == %Discovery.Node{address: "10.0.2.15", node: "default-ubuntu-1204", service_id: "route",
      service_name: "route", service_port: 10100, service_tags: nil}
  end
end
