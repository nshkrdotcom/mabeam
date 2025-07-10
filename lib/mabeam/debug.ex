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
  def log(message, metadata \\ [])

  def log(message, metadata)
      when is_binary(message) and is_list(metadata) do
    if debug_enabled?() do
      Logger.debug(message, metadata)
    end
  end

  def log(message, metadata) when not is_binary(message) do
    if debug_enabled?() do
      Logger.debug("Invalid message type: #{inspect(message)}", metadata)
    end
  end

  def log(message, metadata) when not is_list(metadata) do
    if debug_enabled?() do
      Logger.debug(message, invalid_metadata: metadata)
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
