#
# The MIT License (MIT)
#
# Copyright (c) 2014-2015 Undead Labs, LLC
#

defmodule Discovery.Util do
  @moduledoc """
  A collection of helpful functions.
  """

  @doc """
  Determine if the given application is currently loaded and running.
  """
  @spec app_running?(atom) :: boolean
  def app_running?(name) when is_binary(name), do: String.to_atom(name) |> app_running?
  def app_running?(name) when is_atom(name) do
    :application.which_applications |> _app_running?(name)
  end

  #
  # Private
  #

  defp _app_running?([], _), do: false
  defp _app_running?([app|_], name) when elem(app, 0) == name, do: true
  defp _app_running?([_|rest], name), do: _app_running?(rest, name)
end
