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
    case otp_name(service) do
      nil ->
        {:error, :no_node_name}
      otp_name ->
        Discovery.NodeConnector.connect(otp_name, name)
    end
  end

  defp otp_name(%{tags: []}), do: nil
  defp otp_name(%{tags: tags}) when is_list(tags), do: Keyword.get(tags, :otp_name)
  defp otp_name(_), do: nil
end
