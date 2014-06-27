defmodule Discovery.Handler.NodeConnect do
  use Discovery.Handler.Behaviour
  @passing "passing"
  @critical "critical"
  @warning "warning"

  def update_services([]), do: :ok
  def update_services([%Discovery.Service{status: @critical}|rest]), do: update_services(rest)
  def update_services([%Discovery.Service{status: status} = service|rest]) when status in [@passing, @warning] do
    connect(service)
    update_services(rest)
  end

  #
  # Private API
  #

  defp connect(%Discovery.Service{name: name} = service) do
    Discovery.NodeConnector.connect(node_name(service), name)
  end

  defp node_name(%Discovery.Service{name: service, node: %Discovery.Node{name: node}}) do
    binary_to_atom("#{service}@#{node}")
  end
end
