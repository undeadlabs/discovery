#
# The MIT License (MIT)
#
# Copyright (c) 2014 Undead Labs, LLC
#

defmodule Discovery.Node do
  defstruct name: nil,
    address: nil

  @type t :: %__MODULE__{
    name: binary,
    address: binary
  }
end
