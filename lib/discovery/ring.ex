defmodule Discovery.Ring do
  @moduledoc """
  Manages a consistent hash ring of Erlang nodes for a discovered service.
  """

  defstruct pid: nil :: pid,
    ref: nil :: reference

  def start do
    HashRing.start(replicas: Application.get_env(:discovery, :replica_count, 128))
  end

  defdelegate [
    add(ring, node),
    drop(ring, node),
    stop(ring),
    set_mode(ring, mode),
  ], to: HashRing

  @doc """
  Find a node in a service ring with the given hash key.
  """
  @spec find(binary | atom, binary) :: {:ok, atom} | {:error, term}
  def find(ring, hash) do
    case HashRing.find(ring, hash) do
      {:ok, value} ->
        {:ok, String.to_atom(value)}
      error ->
        error
    end
  end
end
