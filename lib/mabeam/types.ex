defmodule Mabeam.Types do
  @moduledoc """
  Core type definitions for the Mabeam system.
  
  This module defines the foundational types that all components understand,
  providing a consistent type system across the entire framework.
  """
  
  # Basic types that all components understand
  @type agent_id :: binary()
  @type channel_id :: binary()
  @type timestamp :: DateTime.t()
  @type version :: pos_integer()
  
  # Result types for consistent error handling
  @type result(success) :: {:ok, success} | {:error, error()}
  @type result(success, error) :: {:ok, success} | {:error, error}
  @type error :: atom() | {atom(), term()} | Exception.t()
  
  # Async operation types
  @type task_ref :: reference()
  @type async_result(t) :: {:pending, task_ref()} | {:ready, result(t)}
  
  # Container types for flexibility
  @type option(t) :: {:some, t} | :none
  @type either(left, right) :: {:left, left} | {:right, right}
  @type validated(t) :: {:valid, t} | {:invalid, [error()]}
  
  @type stream :: Enumerable.t()
  @type async_stream :: Stream.t()
  
  @type batch(t) :: %{
    items: [t],
    size: pos_integer(),
    metadata: map()
  }
end