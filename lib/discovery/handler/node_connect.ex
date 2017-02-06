#
# The MIT License (MIT)
#
# Copyright (c) 2014-2015 Undead Labs, LLC
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

  require Logger
  use Discovery.Handler.Behaviour
  alias Discovery.Directory
  alias Discovery.Service
  alias Discovery.NodeConnector

  @passing "passing"
  @warning "warning"

  @doc """
  Connect to a list of services. Only services marked passing will be connected to.
  """
  @spec connect([Service.t]) :: :ok
  def connect([]), do: :ok
  def connect([%Service{name: name, status: status} = service|rest]) when status in [@passing, @warning] do
    # interesting that this responds with an error but does nothing with it
    _ = 
    case otp_name(service) do
      nil ->
        {:error, :no_node_name}
      otp_name ->
        Discovery.NodeConnector.connect(otp_name, name)
    end
    connect(rest)
  end
  def connect([_|rest]), do: connect(rest)

  @doc """
  Disconnect from a list of stale services. A list of stale services can be obtained
  by calling `NodeConnect.stale/1` with a list of `Discovery.Service`.
  """
  @spec disconnect([{binary, [atom]}]) :: :ok
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
    Enum.reduce grouped, [], fn({name, nodes}, drop) ->
      {_, unknown} = Enum.partition nodes, fn(node) ->
        Enum.any? given, fn
          %Service{name: sname} = service when sname == name ->
            otp_name(service) == node
          _ ->
            false
        end
      end

      [{name, unknown}|drop]
    end
  end

  #
  # GenEvent callbacks
  #

  def init([]), do: {:ok, []}
  def init(handlers) when is_list(handlers) do
    refs = Enum.map handlers, fn
      {module, args} ->
        {:ok, ref} = NodeConnector.add_handler(module, args)
        ref
      module ->
        {:ok, ref} = NodeConnector.add_handler(module)
        ref
    end
    {:ok, refs}
  end

  def terminate(_, refs) do
    Enum.each refs, fn({module, ref}) ->
      NodeConnector.remove_handler(module, ref)
    end
    :ok
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

  defp otp_name(%{tags: [], node: node}) when node != nil do
    %Discovery.Node{address: address, name: host} = node
    String.to_atom(host <> "@" <> address)
  end

  defp otp_name(%{tags: tags, node: node}) when is_list(tags) do
    case Keyword.get(tags, :otp_name) do
      nil when node != nil ->
        %Discovery.Node{address: address, name: host} = node
        String.to_atom(host <> "@" <> address)
      nil ->
        nil
      name when is_binary(name) ->
        String.to_atom(name)
      name when is_atom(name) ->
        name
    end
  end
  defp otp_name(_), do: nil
end
