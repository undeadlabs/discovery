defmodule Discovery.Service do
  defstruct name: nil :: binary,
    port: nil :: integer,
    status: nil :: binary,
    node: nil :: Discovery.Node.t

  def from_health([]), do: []
  def from_health(checks) when is_list(checks), do: Enum.map(checks, &from_health/1)
  def from_health(%{"Node" => node, "Checks" => checks, "Service" => %{"Service" => name, "Port" => port}}) do
    node = %Discovery.Node{address: node["Address"], name: node["Node"]}
    %__MODULE__{name: name, port: port, status: extract_status(checks, name), node: node}
  end

  #
  # Private API
  #

  defp extract_status([], _), do: nil
  defp extract_status([%{"ServiceName" => service, "Status" => status}|_], service), do: status
  defp extract_status([%{"ServiceName" => _}|rest], service), do: extract_status(rest, service)
end
