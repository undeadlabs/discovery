#
# The MIT License (MIT)
#
# Copyright (c) 2014-2015 Undead Labs, LLC
#

defmodule Discovery.Service do
  defstruct name: nil,
    port: nil,
    status: nil,
    tags: [],
    node: nil

  @type t :: %__MODULE__{
    name: binary,
    port: integer,
    status: binary,
    tags: [binary],
    node: Discovery.Node.t
  }

  @doc """
  Build a `Discovery.Service` struct, or a list of `Discovery.Service` structs, from a list
  of health checks or a health check returned by `Consul.Health.service/1`.
  """
  @spec from_health([map] | map) :: [Discovery.Service.t] | Discovery.Service.t
  def from_health([]), do: []
  def from_health(checks) when is_list(checks), do: Enum.map(checks, &from_health/1)
  def from_health(r) when is_bitstring(r), do: from_health(:jsxn.decode(r))
  def from_health(%{"Node" => node, "Checks" => checks, "Service" => service}) do
    %__MODULE__{name: service["Service"], port: service["Port"], tags: extract_tags(service, node),
      status: extract_status(checks, service), node: %Discovery.Node{address: node["Address"], name: node["Node"]}}
  end
  #
  # Private API
  #

  defp extract_tag(tag) do
    case String.split(tag, ":", parts: 2) do
      [key] ->
        key
      [key, value] ->
        {String.to_atom(key), value}
    end
  end

  defp extract_tags(%{"Tags" => nil}, node), do: extract_tags([], [], node)
  defp extract_tags(%{"Tags" => tags}, node), do: extract_tags(tags, [], node)
  defp extract_tags([], tags, node) do
      if( nil == tags[:otp_name] ) do
        address = node["Address"]
        host    = node["Node"]
        tags = [{:otp_name, node["Node"] <> "@" <> node["Address"]} | tags]
      end
      tags
  end 
  defp extract_tags([tag|rest], acc, node) do
    extract_tags(rest, [extract_tag(tag)|acc], node)
  end

  defp extract_status([], _), do: nil
  defp extract_status([%{"ServiceName" => service, "Status" => status}|_], %{"Service" => service}), do: status
  defp extract_status([%{"ServiceName" => _}|rest], service), do: extract_status(rest, service)
end
