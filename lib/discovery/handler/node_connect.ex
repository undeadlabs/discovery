#
# The MIT License (MIT)
#
# Copyright (c) 2014 Undead Labs, LLC
#

defmodule Discovery.Handler.NodeConnect do
  @moduledoc """
  A poller handler which will instruct the `Discovery.NodeConnector` to attempt to
  establish an OTP connection to the node of found services.

  Consul service definitions exposing a special tag containing their OTP name will be passed
  to `Discovery.NodeConnector` and all other nodes providing services which do not contain
  that tag will be ignored.

  The tag is a colon (`:`) separated string where the first element is the key `otp_name` and
  the second element is a string representation of the OTP node name.

  ### Example Definition

      {
        "service": {
          "name": "my_application",
          "check": {
            "ttl": "15s"
          },
          "tags": [
            "otp_name:my_application@jamie.undeadlabs.com"
          ]
        }
      }
  """

  use Discovery.Handler.Behaviour
  alias Discovery.Directory
  alias Discovery.Service

  @passing "passing"
  @warning "warning"

  def connect([]), do: :ok
  def connect([%Service{name: name, status: status} = service|rest]) when status in [@passing, @warning] do
    case otp_name(service) do
      nil ->
        {:error, :no_node_name}
      otp_name ->
        Discovery.NodeConnector.connect(otp_name, name)
    end
    connect(rest)
  end
  def connect([_|rest]), do: connect(rest)

  def disconnect([]), do: :ok
  def disconnect([{service, nodes}|rest]) do
    _disconnect(service, nodes)
    disconnect(rest)
  end
  defp _disconnect(_, []), do: :ok
  defp _disconnect(service, [node|rest]) do
    Discovery.NodeConnector.disconnect(node, service)
    _disconnect(service, rest)
  end

  @doc """
  Returns a list of stale registered nodes in `Discovery.Directory` which are no longer
  providing a service given the list of fresh services.

  The return value is a list of tuples where the first element is a service name and
  the second element is a list of node names which are providing that service.

  ### Example

      [{"router", [:"reset@undead"]}]
  """
  def stale(given) do
    service_names = Enum.map(given, fn(%Service{name: name}) -> name end) |> Enum.uniq
    grouped       = for name <- service_names, do: {name, Directory.nodes(name)}
    Enum.reduce(grouped, [], fn({name, nodes}, drop) ->
      {_, unknown} = Enum.partition(nodes, fn(node) ->
        Enum.any?(given, fn
          %Service{name: sname} = service when sname == name ->
            otp_name(service) == node
          _ ->
            false
        end)
      end)

      [{name, unknown}|drop]
    end)
  end

  #
  # Discovery.Handler.Behaviour callbacks
  #

  def handle_services(services, state) do
    stale(services) |> disconnect
    connect(services)
    {:ok, state}
  end

  #
  # Private
  #

  defp otp_name(%{tags: []}), do: nil
  defp otp_name(%{tags: tags}) when is_list(tags) do
    case Keyword.get(tags, :otp_name) do
      nil ->
        nil
      name ->
        String.to_atom(name)
    end
  end
  defp otp_name(_), do: nil
end
