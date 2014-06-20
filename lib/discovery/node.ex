defmodule Discovery.Node do
  defstruct node: nil :: binary,
    address: nil :: binary,
    service_id: nil :: binary,
    service_name: nil :: binary,
    service_tags: nil :: binary,
    service_port: nil :: integer

  @doc """
  Build a list of Discovery.Node structs from a consul response containing multiple nodes.
  """
  def build(nodes) when is_list(nodes) do
    Enum.map(nodes, &build/1)
  end

  @doc """
  Build a single Discovery.Node struct from a consul response containing a single node.
  """
  def build(%{"Address" => address, "Node" => node, "ServiceID" => id, "ServiceName" => name, "ServicePort" => port,
    "ServiceTags" => tags}) do
    %__MODULE__{node: node, address: address, service_id: id, service_name: name, service_tags: tags, service_port: port}
  end
end
