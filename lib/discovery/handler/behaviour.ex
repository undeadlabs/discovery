#
# The MIT License (MIT)
#
# Copyright (c) 2014 Undead Labs, LLC
#

defmodule Discovery.Handler.Behaviour do
  use Behaviour

  defmacro __using__(_) do
    quote do
      @behaviour unquote(__MODULE__)
      use GenEvent

      #
      # GenEvent callbacks
      #

      def handle_event({:services, services}, state) do
        update_services(services)
        {:ok, state}
      end
    end
  end

  defcallback update_services(services :: [Discovery.Service.t])
end
