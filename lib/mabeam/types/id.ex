defmodule Mabeam.Types.ID do
  @moduledoc """
  Type-safe ID generation and management.

  This module provides utilities for generating and managing
  different types of IDs with compile-time safety.
  """

  use TypedStruct

  @type id_type :: :agent | :channel | :instruction | :event | :signal | :message

  typedstruct module: TypedID do
    @moduledoc """
    A type-safe ID wrapper that prevents mixing different ID types.
    """

    field(:value, binary(), enforce: true)
    field(:type, Mabeam.Types.ID.id_type(), enforce: true)
    field(:created_at, DateTime.t(), enforce: true)
  end

  @type t :: TypedID.t()

  @doc """
  Generates a new agent ID.

  ## Examples

      iex> agent_id = Mabeam.Types.ID.agent_id()
      %Mabeam.Types.ID.TypedID{value: "agent_" <> _, type: :agent}
  """
  @spec agent_id() :: t()
  def agent_id do
    %TypedID{
      value: "agent_" <> UUID.uuid4(),
      type: :agent,
      created_at: DateTime.utc_now()
    }
  end

  @doc """
  Generates a new channel ID.

  ## Examples

      iex> channel_id = Mabeam.Types.ID.channel_id()
      %Mabeam.Types.ID.TypedID{value: "channel_" <> _, type: :channel}
  """
  @spec channel_id() :: t()
  def channel_id do
    %TypedID{
      value: "channel_" <> UUID.uuid4(),
      type: :channel,
      created_at: DateTime.utc_now()
    }
  end

  @doc """
  Generates a new instruction ID.

  ## Examples

      iex> instruction_id = Mabeam.Types.ID.instruction_id()
      %Mabeam.Types.ID.TypedID{value: "instruction_" <> _, type: :instruction}
  """
  @spec instruction_id() :: t()
  def instruction_id do
    %TypedID{
      value: "instruction_" <> UUID.uuid4(),
      type: :instruction,
      created_at: DateTime.utc_now()
    }
  end

  @doc """
  Generates a new event ID.

  ## Examples

      iex> event_id = Mabeam.Types.ID.event_id()
      %Mabeam.Types.ID.TypedID{value: "event_" <> _, type: :event}
  """
  @spec event_id() :: t()
  def event_id do
    %TypedID{
      value: "event_" <> UUID.uuid4(),
      type: :event,
      created_at: DateTime.utc_now()
    }
  end

  @doc """
  Generates a new signal ID.

  ## Examples

      iex> signal_id = Mabeam.Types.ID.signal_id()
      %Mabeam.Types.ID.TypedID{value: "signal_" <> _, type: :signal}
  """
  @spec signal_id() :: t()
  def signal_id do
    %TypedID{
      value: "signal_" <> UUID.uuid4(),
      type: :signal,
      created_at: DateTime.utc_now()
    }
  end

  @doc """
  Generates a new message ID.

  ## Examples

      iex> message_id = Mabeam.Types.ID.message_id()
      %Mabeam.Types.ID.TypedID{value: "message_" <> _, type: :message}
  """
  @spec message_id() :: t()
  def message_id do
    %TypedID{
      value: "message_" <> UUID.uuid4(),
      type: :message,
      created_at: DateTime.utc_now()
    }
  end

  @doc """
  Unwraps a typed ID to get the string value.

  ## Examples

      iex> id = Mabeam.Types.ID.agent_id()
      iex> Mabeam.Types.ID.unwrap(id)
      "agent_" <> _
  """
  @spec unwrap(t()) :: binary()
  def unwrap(%TypedID{value: value}), do: value

  @doc """
  Gets the type of a typed ID.

  ## Examples

      iex> id = Mabeam.Types.ID.agent_id()
      iex> Mabeam.Types.ID.get_type(id)
      :agent
  """
  @spec get_type(t()) :: id_type()
  def get_type(%TypedID{type: type}), do: type

  @doc """
  Checks if an ID is of a specific type.

  ## Examples

      iex> id = Mabeam.Types.ID.agent_id()
      iex> Mabeam.Types.ID.is_type?(id, :agent)
      true
      iex> Mabeam.Types.ID.is_type?(id, :channel)
      false
  """
  @spec is_type?(t(), id_type()) :: boolean()
  def is_type?(%TypedID{type: type}, expected_type), do: type == expected_type

  @doc """
  Creates a typed ID from a string value and type.

  This function should be used carefully as it bypasses the
  type-safe generation functions.

  ## Examples

      iex> id = Mabeam.Types.ID.from_string("agent_123", :agent)
      %Mabeam.Types.ID.TypedID{value: "agent_123", type: :agent}
  """
  @spec from_string(binary(), id_type()) :: t()
  def from_string(value, type) when is_binary(value) do
    %TypedID{
      value: value,
      type: type,
      created_at: DateTime.utc_now()
    }
  end
end
