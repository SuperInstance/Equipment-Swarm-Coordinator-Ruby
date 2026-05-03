# frozen_string_literal: true

require_relative 'types'

module SuperInstance
  module Equipment
    module SwarmCoordinator
      # Configuration for the Agent Orchestrator
      OrchestratorConfig = Data.define(
        :max_agents,
        :enable_hierarchy,
        :max_hierarchy_depth,
        :default_timeout,
        :load_balancing
      ) do
        def self.new(**kwargs)
          defaults = {
            max_agents: 100,
            enable_hierarchy: true,
            max_hierarchy_depth: 5,
            default_timeout: 30_000,
            load_balancing: true
          }
          super(**defaults.merge(kwargs))
        end
      end

      # Profile of an agent in the swarm
      AgentProfile = Data.define(
        :id,
        :name,
        :role,
        :capabilities,
        :status,
        :hierarchy_level,
        :parent_agent_id,
        :child_agent_ids,
        :metadata,
        :current_load,
        :weight
      )

      # Result of an orchestration operation
      OrchestrationResult = Data.define(
        :success,
        :data,
        :error,
        :agents_involved,
        :execution_time,
        :timestamp
      )

      # Node in the agent hierarchy tree
      AgentHierarchyNode = Data.define(
        :agent,
        :children
      )

      # Statistics about the orchestrator
      OrchestratorStatistics = Data.define(
        :total_agents,
        :agents_by_role,
        :agents_by_status,
        :average_load,
        :hierarchy_depth,
        :top_performers
      )

      # AgentOrchestrator manages agent registration, hierarchy, and task distribution.
      class AgentOrchestrator
        attr_reader :config

        # Creates a new AgentOrchestrator
        # @param config [Hash] Configuration options
        def initialize(config = {})
          @config = OrchestratorConfig.new(**config)
          @agents = {}
          @hierarchy = {}
          @agent_weights = {}
        end

        # Register a new agent
        # @param profile [AgentProfile] Agent profile
        # @return [Boolean] True if registration successful
        def register_agent(profile)
          return false if @agents.size >= @config.max_agents
          return false if @agents.key?(profile.id)

          if profile.hierarchy_level > @config.max_hierarchy_depth
            return false
          end

          full_profile = profile.with(
            child_agent_ids: [],
            current_load: 0,
            weight: 1.0
          )

          @agents[profile.id] = full_profile
          @agent_weights[profile.id] = 1.0
          @hierarchy[profile.id] = Set.new

          if profile.parent_agent_id && @agents.key?(profile.parent_agent_id)
            parent = @agents[profile.parent_agent_id]
            updated_children = parent.child_agent_ids + [profile.id]
            @agents[profile.parent_agent_id] = parent.with(child_agent_ids: updated_children)
            @hierarchy[profile.parent_agent_id].add(profile.id)
          end

          true
        end

        # Unregister an agent
        # @param agent_id [String] Agent identifier
        # @return [Boolean] True if unregistration successful
        def unregister_agent(agent_id)
          return false unless @agents.key?(agent_id)

          agent = @agents[agent_id]

          agent.child_agent_ids.each do |child_id|
            child = @agents[child_id]
            if child
              @agents[child_id] = child.with(
                parent_agent_id: agent.parent_agent_id,
                hierarchy_level: [0, child.hierarchy_level - 1].max
              )
            end
          end

          if agent.parent_agent_id
            parent = @agents[agent.parent_agent_id]
            if parent
              updated_children = parent.child_agent_ids.reject { |id| id == agent_id }
              @agents[agent.parent_agent_id] = parent.with(child_agent_ids: updated_children)
              @hierarchy[agent.parent_agent_id].delete(agent_id)
            end
          end

          @agents.delete(agent_id)
          @agent_weights.delete(agent_id)
          @hierarchy.delete(agent_id)

          true
        end

        # Get agent profile
        # @param agent_id [String] Agent identifier
        # @return [AgentProfile, nil] Agent profile or undefined
        def get_agent(agent_id)
          @agents[agent_id]
        end

        # Get all agents
        # @return [Array<AgentProfile>] Array of all agent profiles
        def get_all_agents
          @agents.values
        end

        # Get agents by role
        # @param role [Symbol] Role to filter by
        # @return [Array<AgentProfile>] Agents with specified role
        def get_agents_by_role(role)
          @agents.values.select { |agent| agent.role == role }
        end

        # Get agents by capability
        # @param capability [String] Capability to filter by
        # @return [Array<AgentProfile>] Agents with specified capability
        def get_agents_by_capability(capability)
          @agents.values.select { |agent| agent.capabilities.include?(capability) }
        end

        # Get available agents (idle status)
        # @return [Array<AgentProfile>] Available agents
        def get_available_agents
          @agents.values.select do |agent|
            agent.status == Types::ExecutionStatus::IDLE && agent.current_load < 1
          end
        end

        # Get agent hierarchy
        # @param agent_id [String] Root agent ID
        # @return [AgentHierarchyNode, nil] Hierarchy tree
        def get_hierarchy(agent_id)
          agent = @agents[agent_id]
          return nil unless agent

          build_hierarchy_node(agent)
        end

        # Update agent status
        # @param agent_id [String] Agent identifier
        # @param status [Symbol] New status
        def update_agent_status(agent_id, status)
          agent = @agents[agent_id]
          @agents[agent_id] = agent.with(status: status) if agent
        end

        # Update agent load
        # @param agent_id [String] Agent identifier
        # @param load [Float] Current load (0-1)
        def update_agent_load(agent_id, load)
          agent = @agents[agent_id]
          if agent
            @agents[agent_id] = agent.with(current_load: [0, [1, load].min].max)
          end
        end

        # Adjust agent weight for task allocation
        # @param agent_id [String] Agent identifier
        # @param performance_score [Float] Performance score (0-1)
        def adjust_agent_weight(agent_id, performance_score)
          current_weight = @agent_weights[agent_id] || 1.0
          new_weight = current_weight * 0.7 + performance_score * 0.3

          @agent_weights[agent_id] = new_weight

          agent = @agents[agent_id]
          @agents[agent_id] = agent.with(weight: new_weight) if agent
        end

        # Get agent weight
        # @param agent_id [String] Agent identifier
        # @return [Float] Agent weight
        def get_agent_weight(agent_id)
          @agent_weights[agent_id] || 1.0
        end

        # Select best agent for a task
        # @param required_capabilities [Array<String>] Required capabilities
        # @param preferred_role [Symbol, nil] Preferred agent role
        # @return [AgentProfile, nil] Best agent or undefined
        def select_best_agent(required_capabilities, preferred_role = nil)
          candidates = get_available_agents.select do |agent|
            required_capabilities.all? { |cap| agent.capabilities.include?(cap) }
          end

          return nil if candidates.empty?

          role_matched = preferred_role ? candidates.select { |a| a.role == preferred_role } : candidates
          pool = role_matched.empty? ? candidates : role_matched

          pool.sort_by do |a|
            [-a.weight, a.current_load]
          end.first
        end

        # Broadcast message to all agents
        # @param message [Object] Message to broadcast
        # @param exclude_agent_ids [Array<String>] Agents to exclude
        # @return [Hash<String, OrchestrationResult>] Results map
        def broadcast(message, exclude_agent_ids = [])
          results = {}

          @agents.each do |agent_id, agent|
            next if exclude_agent_ids.include?(agent_id)

            results[agent_id] = OrchestrationResult.new(
              success: true,
              data: message,
              agents_involved: [agent_id],
              execution_time: 0,
              timestamp: DateTime.now
            )
          end

          results
        end

        # Send message to specific agents
        # @param agent_ids [Array<String>] Target agent IDs
        # @param message [Object] Message to send
        # @return [Hash<String, OrchestrationResult>] Results map
        def multicast(agent_ids, message)
          results = {}

          agent_ids.each do |agent_id|
            if @agents.key?(agent_id)
              results[agent_id] = OrchestrationResult.new(
                success: true,
                data: message,
                agents_involved: [agent_id],
                execution_time: 0,
                timestamp: DateTime.now
              )
            end
          end

          results
        end

        # Get orchestrator statistics
        # @return [OrchestratorStatistics] Statistics object
        def get_statistics
          agents = @agents.values

          {
            total_agents: agents.size,
            agents_by_role: group_by_role(agents),
            agents_by_status: group_by_status(agents),
            average_load: calculate_average_load(agents),
            hierarchy_depth: calculate_max_depth,
            top_performers: get_top_performers(5)
          }
        end

        private

        def build_hierarchy_node(agent)
          children = agent.child_agent_ids.filter_map { |child_id| get_hierarchy(child_id) }

          AgentHierarchyNode.new(
            agent: agent,
            children: children
          )
        end

        def group_by_role(agents)
          {
            Types::AgentRole::COORDINATOR => agents.count { |a| a.role == Types::AgentRole::COORDINATOR },
            Types::AgentRole::EXECUTOR => agents.count { |a| a.role == Types::AgentRole::EXECUTOR },
            Types::AgentRole::OBSERVER => agents.count { |a| a.role == Types::AgentRole::OBSERVER },
            Types::AgentRole::VALIDATOR => agents.count { |a| a.role == Types::AgentRole::VALIDATOR },
            Types::AgentRole::SPECIALIST => agents.count { |a| a.role == Types::AgentRole::SPECIALIST }
          }
        end

        def group_by_status(agents)
          {
            Types::ExecutionStatus::IDLE => agents.count { |a| a.status == Types::ExecutionStatus::IDLE },
            Types::ExecutionStatus::RUNNING => agents.count { |a| a.status == Types::ExecutionStatus::RUNNING },
            Types::ExecutionStatus::PAUSED => agents.count { |a| a.status == Types::ExecutionStatus::PAUSED },
            Types::ExecutionStatus::COMPLETED => agents.count { |a| a.status == Types::ExecutionStatus::COMPLETED },
            Types::ExecutionStatus::FAILED => agents.count { |a| a.status == Types::ExecutionStatus::FAILED }
          }
        end

        def calculate_average_load(agents)
          return 0 if agents.empty?
          agents.sum(&:current_load).to_f / agents.size
        end

        def calculate_max_depth
          roots = @agents.values.select { |a| a.parent_agent_id.nil? }
          return 0 if roots.empty?

          roots.map { |root| calculate_depth(root.id, 0) }.max
        end

        def calculate_depth(agent_id, current_depth)
          agent = @agents[agent_id]
          return current_depth unless agent

          max_child_depth = current_depth + 1

          agent.child_agent_ids.each do |child_id|
            child_depth = calculate_depth(child_id, current_depth + 1)
            max_child_depth = [max_child_depth, child_depth].max
          end

          max_child_depth
        end

        def get_top_performers(count)
          @agents.values
            .sort_by { |a| -a.weight }
            .take(count)
        end
      end
    end
  end
end
