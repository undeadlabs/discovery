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
        handle_services(services, state)
      end
    end
  end

  defcallback handle_services(services :: [Discovery.Service.t], state :: term)
end
