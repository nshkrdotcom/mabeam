defmodule Mabeam.Types.Communication do
  @moduledoc """
  Communication-specific types for the Mabeam system.

  This module defines types for events, signals, and messages used
  throughout the system for agent communication.
  """

  use TypedStruct

  @type agent_id :: Mabeam.Types.agent_id()
  @type timestamp :: Mabeam.Types.timestamp()

  # Event types
  typedstruct module: Event do
    @moduledoc """
    Event structure for broadcast communication.

    Events are used for broadcasting information to multiple
    subscribers without expecting a response.
    """

    field(:id, String.t(), enforce: true)
    field(:type, atom(), enforce: true)
    field(:source, Mabeam.Types.agent_id() | pid(), enforce: true)
    field(:data, term())
    field(:metadata, map(), default: %{})
    field(:timestamp, Mabeam.Types.timestamp(), enforce: true)
  end

  @type event :: Event.t()

  # Signal types
  @type signal_priority :: :low | :normal | :high
  @type signal_target :: :broadcast | agent_id() | [agent_id()]

  typedstruct module: Signal do
    @moduledoc """
    Signal structure for targeted communication.

    Signals are used for direct communication between agents
    with priority handling.
    """

    field(:id, String.t(), enforce: true)
    field(:type, atom(), enforce: true)
    field(:source, Mabeam.Types.agent_id(), enforce: true)
    field(:target, Mabeam.Types.Communication.signal_target(), enforce: true)
    field(:data, term())
    field(:priority, Mabeam.Types.Communication.signal_priority(), default: :normal)
    field(:metadata, map(), default: %{})
    field(:timestamp, Mabeam.Types.timestamp(), enforce: true)
  end

  @type signal :: Signal.t()

  # Message types
  typedstruct module: Message do
    @moduledoc """
    Message structure for request-response communication.

    Messages are used for request-response patterns with
    correlation IDs and reply-to addresses.
    """

    field(:id, String.t(), enforce: true)
    field(:type, atom(), enforce: true)
    field(:source, Mabeam.Types.agent_id(), enforce: true)
    field(:target, Mabeam.Types.agent_id(), enforce: true)
    field(:data, term())
    field(:reply_to, Mabeam.Types.agent_id() | pid() | nil)
    field(:correlation_id, String.t() | nil)
    field(:timeout, pos_integer(), default: 5000)
    field(:metadata, map(), default: %{})
    field(:timestamp, Mabeam.Types.timestamp(), enforce: true)
  end

  @type message :: Message.t()

  # Routing types
  @type routing_pattern :: atom() | {atom(), atom()} | function()

  typedstruct module: RoutingRule do
    @moduledoc """
    Routing rule for message/signal routing.

    Defines how messages and signals should be routed
    through the system.
    """

    field(:pattern, Mabeam.Types.Communication.routing_pattern(), enforce: true)
    field(:transformer, function() | nil)
    field(:filter, function() | nil)
    field(:metadata, map(), default: %{})
  end

  @type routing_rule :: RoutingRule.t()
end
