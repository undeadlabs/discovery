defmodule Discovery.Service do
  defstruct id: nil :: binary,
    port: nil :: integer,
    service: nil :: binary,
    tags: [] :: list
end
