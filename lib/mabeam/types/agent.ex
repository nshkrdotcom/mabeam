defmodule Mabeam.Types.Agent do
  @moduledoc """
  Agent-specific types for the Mabeam system.
  
  This module defines types specific to agents and their operations.
  """
  
  use TypedStruct
  
  @type state :: map()
  @type agent_type :: atom()
  @type capability :: atom()
  @type lifecycle_state :: :initializing | :ready | :busy | :suspended | :terminating
  
  @type agent_id :: Mabeam.Types.agent_id()
  @type result(t) :: Mabeam.Types.result(t)
  @type timestamp :: Mabeam.Types.timestamp()
  @type version :: Mabeam.Types.version()
  
  typedstruct module: Agent do
    @moduledoc """
    Core agent data structure.
    
    This struct contains the essential information about an agent,
    separate from its process state.
    """
    
    field :id, Mabeam.Types.agent_id(), enforce: true
    field :type, Mabeam.Types.Agent.agent_type(), enforce: true
    field :state, Mabeam.Types.Agent.state(), default: %{}
    field :capabilities, [Mabeam.Types.Agent.capability()], default: []
    field :lifecycle, Mabeam.Types.Agent.lifecycle_state(), default: :initializing
    field :version, Mabeam.Types.version(), default: 1
    field :parent_id, Mabeam.Types.agent_id() | nil
    field :metadata, map(), default: %{}
    field :created_at, Mabeam.Types.timestamp(), enforce: true
    field :updated_at, Mabeam.Types.timestamp(), enforce: true
  end
  
  @type t :: Agent.t()
  
  # Action-related types
  @type action_name :: atom()
  @type action_params :: map()
  @type action_result :: term()
  
  typedstruct module: Action do
    @moduledoc """
    Action definition structure.
    
    Defines what an action is and how it should be executed.
    """
    
    field :name, Mabeam.Types.Agent.action_name(), enforce: true
    field :module, module(), enforce: true
    field :description, String.t() | nil
    field :params_schema, keyword() | nil
    field :metadata, map(), default: %{}
  end
  
  @type action :: Action.t()
  
  # Instruction types
  typedstruct module: Instruction do
    @moduledoc """
    Instruction for agent execution.
    
    Represents a single instruction to be executed by an agent.
    """
    
    field :id, String.t(), enforce: true
    field :action, Mabeam.Types.Agent.action_name(), enforce: true
    field :params, Mabeam.Types.Agent.action_params(), default: %{}
    field :context, map(), default: %{}
    field :created_at, Mabeam.Types.timestamp(), enforce: true
  end
  
  @type instruction :: Instruction.t()
  @type instructions :: [instruction()]
end