defmodule Mabeam.Debug do
  @moduledoc """
  Debug utilities for conditional logging.

  This module provides functions to conditionally log debug messages
  based on configuration settings.
  """

  require Logger

  @doc """
  Logs a debug message if debugging is enabled.

  ## Parameters

  - `message`: The message to log
  - `metadata`: Optional metadata (keyword list)

  ## Configuration

  Set `config :mabeam, Mabeam, debug: true` to enable debug logging.
  """
  def log(message, metadata \\ []) do
    if debug_enabled?() do
      Logger.debug(message, metadata)
    end
  end

  @doc """
  Checks if debug logging is enabled.
  """
  def debug_enabled?() do
    config = Application.get_env(:mabeam, Mabeam, [])
    Keyword.get(config, :debug, false)
  end
end
