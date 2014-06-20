defmodule Discovery.Handler.Behaviour do
  use Behaviour

  defmacro __using__(_) do
    quote do
      @behaviour unquote(__MODULE__)
      use GenEvent

      #
      # GenEvent callbacks
      #

      def handle_event({:nodes, nodes}, state) do
        update_nodes(nodes)
        {:ok, state}
      end
    end
  end

  defcallback update_nodes(nodes :: [Discovery.Node.t])
end
