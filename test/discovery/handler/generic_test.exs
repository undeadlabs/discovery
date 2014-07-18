defmodule Discovery.Handler.GenericTest do
  use ExUnit.Case
  alias Discovery.Handler.Generic

  setup do
    {:ok, em} = GenEvent.start

    on_exit fn ->
      GenEvent.stop(em)
    end

    {:ok, em: em}
  end

  test "calls the function with the services when event is received", ctx do
    this = self
    fun  = fn(services) ->
      send(this, {:services, services})
    end

    :ok = GenEvent.add_handler(ctx[:em], Generic, [fun])
    :ok = GenEvent.sync_notify(ctx[:em], {:services, []})

    assert_received {:services, []}
  end
end
