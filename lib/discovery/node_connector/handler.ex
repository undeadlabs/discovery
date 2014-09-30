#
# The MIT License (MIT)
#
# Copyright (c) 2014 Undead Labs, LLC
#

defmodule Discovery.NodeConnector.Handler do
  use Behaviour

  @spec notify_connect(pid, node) :: :ok
  def notify_connect(em, node) do
    GenEvent.notify(em, {:connect, node})
  end

  @spec notify_disconnect(pid, node) :: :ok
  def notify_disconnect(em, node) do
    GenEvent.notify(em, {:disconnect, node})
  end

  defmacro __using__(_) do
    quote do
      @behaviour unquote(__MODULE__)
      use GenEvent
      alias Discovery.Directory

      #
      # GenEvent callbacks
      #

      def handle_event({:connect, node}, state) do
        on_connect(node, Directory.services(node))
        {:ok, state}
      end

      def handle_event({:disconnect, node}, state) do
        on_disconnect(node, Directory.services(node))
        {:ok, state}
      end
    end
  end

  defcallback on_connect(node :: node, service :: binary)
  defcallback on_disconnect(node :: node, services :: [binary])
end
