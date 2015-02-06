#
# The MIT License (MIT)
#
# Copyright (c) 2014-2015 Undead Labs, LLC
#

defmodule Discovery.Handler.Generic do
  use Discovery.Handler.Behaviour

  def init([fun]) when is_function(fun, 1) do
    {:ok, %{fun: fun}}
  end

  def handle_services(services, %{fun: fun} = state) do
    fun.(services)
    {:ok, state}
  end
end
