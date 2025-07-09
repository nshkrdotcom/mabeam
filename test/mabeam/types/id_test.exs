defmodule Mabeam.Types.IDTest do
  use ExUnit.Case
  alias Mabeam.Types.ID
  
  describe "agent_id/0" do
    test "generates a unique agent ID" do
      id1 = ID.agent_id()
      id2 = ID.agent_id()
      
      assert id1 != id2
      assert ID.get_type(id1) == :agent
      assert ID.get_type(id2) == :agent
      assert String.starts_with?(ID.unwrap(id1), "agent_")
      assert String.starts_with?(ID.unwrap(id2), "agent_")
    end
    
    test "creates a properly structured ID" do
      id = ID.agent_id()
      
      assert %ID.TypedID{} = id
      assert id.type == :agent
      assert is_binary(id.value)
      assert %DateTime{} = id.created_at
    end
  end
  
  describe "channel_id/0" do
    test "generates a unique channel ID" do
      id1 = ID.channel_id()
      id2 = ID.channel_id()
      
      assert id1 != id2
      assert ID.get_type(id1) == :channel
      assert ID.get_type(id2) == :channel
      assert String.starts_with?(ID.unwrap(id1), "channel_")
      assert String.starts_with?(ID.unwrap(id2), "channel_")
    end
  end
  
  describe "instruction_id/0" do
    test "generates a unique instruction ID" do
      id1 = ID.instruction_id()
      id2 = ID.instruction_id()
      
      assert id1 != id2
      assert ID.get_type(id1) == :instruction
      assert ID.get_type(id2) == :instruction
      assert String.starts_with?(ID.unwrap(id1), "instruction_")
      assert String.starts_with?(ID.unwrap(id2), "instruction_")
    end
  end
  
  describe "unwrap/1" do
    test "extracts the string value from a typed ID" do
      id = ID.agent_id()
      unwrapped = ID.unwrap(id)
      
      assert is_binary(unwrapped)
      assert String.starts_with?(unwrapped, "agent_")
    end
  end
  
  describe "get_type/1" do
    test "returns the correct type for each ID type" do
      agent_id = ID.agent_id()
      channel_id = ID.channel_id()
      instruction_id = ID.instruction_id()
      
      assert ID.get_type(agent_id) == :agent
      assert ID.get_type(channel_id) == :channel
      assert ID.get_type(instruction_id) == :instruction
    end
  end
  
  describe "is_type?/2" do
    test "correctly identifies ID types" do
      agent_id = ID.agent_id()
      channel_id = ID.channel_id()
      
      assert ID.is_type?(agent_id, :agent)
      assert not ID.is_type?(agent_id, :channel)
      
      assert ID.is_type?(channel_id, :channel)
      assert not ID.is_type?(channel_id, :agent)
    end
  end
  
  describe "from_string/2" do
    test "creates a typed ID from string and type" do
      id = ID.from_string("test_123", :agent)
      
      assert ID.get_type(id) == :agent
      assert ID.unwrap(id) == "test_123"
      assert %DateTime{} = id.created_at
    end
  end
end