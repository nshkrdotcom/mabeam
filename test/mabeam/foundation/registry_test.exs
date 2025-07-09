defmodule Mabeam.Foundation.RegistryTest do
  use ExUnit.Case
  alias Mabeam.Foundation.Registry
  alias Mabeam.Types.Agent.Agent
  alias Mabeam.Types.ID
  
  setup do
    # Use the existing registry from the application
    # Registry is already started and registered as __MODULE__
    
    # Create a test agent
    agent = %Agent{
      id: ID.agent_id() |> ID.unwrap(),
      type: :test_agent,
      state: %{test: true},
      capabilities: [:test_capability],
      lifecycle: :ready,
      version: 1,
      created_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }
    
    %{registry: Registry, agent: agent}
  end
  
  describe "register/2" do
    test "registers an agent successfully", %{agent: agent} do
      {:ok, mock_pid} = Task.start_link(fn -> 
        receive do
          :shutdown -> :ok
        end
      end)
      
      assert :ok = Registry.register(agent, mock_pid)
      assert {:ok, registered_agent} = Registry.get_agent(agent.id)
      assert registered_agent.id == agent.id
      assert registered_agent.type == agent.type
      
      # Clean up
      Process.exit(mock_pid, :normal)
    end
    
    test "prevents duplicate registrations", %{agent: agent} do
      {:ok, mock_pid} = Task.start_link(fn -> 
        receive do
          :shutdown -> :ok
        end
      end)
      
      assert :ok = Registry.register(agent, mock_pid)
      assert {:error, :already_registered} = Registry.register(agent, mock_pid)
      
      # Clean up
      Process.exit(mock_pid, :normal)
    end
    
    test "monitors registered processes", %{agent: agent} do
      {:ok, mock_pid} = Task.start(fn -> 
        receive do
          :shutdown -> :ok
        end
      end)
      
      assert :ok = Registry.register(agent, mock_pid)
      assert {:ok, _} = Registry.get_agent(agent.id)
      
      # Kill the process
      Process.exit(mock_pid, :kill)
      
      # Give the registry time to process the DOWN message
      Process.sleep(10)
      
      # Agent should be automatically unregistered
      assert {:error, :not_found} = Registry.get_agent(agent.id)
    end
  end
  
  describe "get_agent/1" do
    test "retrieves a registered agent", %{agent: agent} do
      {:ok, mock_pid} = Task.start_link(fn -> 
        receive do
          :shutdown -> :ok
        end
      end)
      
      assert :ok = Registry.register(agent, mock_pid)
      assert {:ok, retrieved_agent} = Registry.get_agent(agent.id)
      assert retrieved_agent.id == agent.id
      
      # Clean up
      Process.exit(mock_pid, :normal)
    end
    
    test "returns error for non-existent agent" do
      assert {:error, :not_found} = Registry.get_agent("non_existent_id")
    end
  end
  
  describe "get_process/1" do
    test "retrieves the process for a registered agent", %{agent: agent} do
      {:ok, mock_pid} = Task.start_link(fn -> 
        receive do
          :shutdown -> :ok
        end
      end)
      
      assert :ok = Registry.register(agent, mock_pid)
      assert {:ok, retrieved_pid} = Registry.get_process(agent.id)
      assert retrieved_pid == mock_pid
      
      # Clean up
      Process.exit(mock_pid, :normal)
    end
    
    test "returns error for non-existent agent" do
      assert {:error, :not_found} = Registry.get_process("non_existent_id")
    end
  end
  
  describe "find_by_type/1" do
    test "finds agents by type", %{agent: agent} do
      {:ok, mock_pid} = Task.start_link(fn -> 
        receive do
          :shutdown -> :ok
        end
      end)
      
      assert :ok = Registry.register(agent, mock_pid)
      
      agents = Registry.find_by_type(:test_agent)
      assert length(agents) == 1
      assert hd(agents).id == agent.id
      
      # Test with non-existent type
      assert Registry.find_by_type(:non_existent_type) == []
      
      # Clean up
      Process.exit(mock_pid, :normal)
    end
  end
  
  describe "find_by_capability/1" do
    test "finds agents by capability", %{agent: agent} do
      {:ok, mock_pid} = Task.start_link(fn -> 
        receive do
          :shutdown -> :ok
        end
      end)
      
      assert :ok = Registry.register(agent, mock_pid)
      
      agents = Registry.find_by_capability(:test_capability)
      assert length(agents) == 1
      assert hd(agents).id == agent.id
      
      # Test with non-existent capability
      assert Registry.find_by_capability(:non_existent_capability) == []
      
      # Clean up
      Process.exit(mock_pid, :normal)
    end
  end
  
  describe "update_agent/2" do
    test "updates agent data", %{agent: agent} do
      {:ok, mock_pid} = Task.start_link(fn -> 
        receive do
          :shutdown -> :ok
        end
      end)
      
      assert :ok = Registry.register(agent, mock_pid)
      
      update_fn = fn agent -> %{agent | state: %{updated: true}} end
      assert {:ok, updated_agent} = Registry.update_agent(agent.id, update_fn)
      assert updated_agent.state.updated == true
      
      # Verify the update persisted
      assert {:ok, retrieved_agent} = Registry.get_agent(agent.id)
      assert retrieved_agent.state.updated == true
      
      # Clean up
      Process.exit(mock_pid, :normal)
    end
    
    test "returns error for non-existent agent" do
      update_fn = fn agent -> agent end
      assert {:error, :not_found} = Registry.update_agent("non_existent_id", update_fn)
    end
  end
  
  describe "list_all/0" do
    test "lists all registered agents", %{agent: agent} do
      {:ok, mock_pid} = Task.start_link(fn -> 
        receive do
          :shutdown -> :ok
        end
      end)
      
      # Clear any existing agents first
      initial_agents = Registry.list_all()
      Enum.each(initial_agents, fn agent ->
        Registry.unregister(agent.id)
      end)
      
      # Should now be empty
      assert Registry.list_all() == []
      
      # Register agent
      assert :ok = Registry.register(agent, mock_pid)
      
      # Should now contain the agent
      agents = Registry.list_all()
      assert length(agents) == 1
      assert hd(agents).id == agent.id
      
      # Clean up
      Process.exit(mock_pid, :normal)
    end
  end
  
  describe "unregister/1" do
    test "manually unregisters an agent", %{agent: agent} do
      {:ok, mock_pid} = Task.start_link(fn -> 
        receive do
          :shutdown -> :ok
        end
      end)
      
      assert :ok = Registry.register(agent, mock_pid)
      assert {:ok, _} = Registry.get_agent(agent.id)
      
      assert :ok = Registry.unregister(agent.id)
      assert {:error, :not_found} = Registry.get_agent(agent.id)
      
      # Clean up
      Process.exit(mock_pid, :normal)
    end
    
    test "returns ok for non-existent agent" do
      assert :ok = Registry.unregister("non_existent_id")
    end
  end
end