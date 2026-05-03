# frozen_string_literal: true

require_relative 'types'
require_relative 'agent_orchestrator'
require_relative 'asymmetric_knowledge'
require_relative 'task_decomposer'
require_relative 'result_aggregator'

module SuperInstance
  module Equipment
    module SwarmCoordinator
      # Configuration for the Swarm Coordinator
      SwarmConfig = Data.define(
        :max_agents,
        :enable_hierarchy,
        :max_hierarchy_depth,
        :knowledge_isolation,
        :task_timeout,
        :adaptive_allocation,
        :conflict_resolution,
        :performance_window_size
      ) do
        def self.new(**kwargs)
          defaults = {
            max_agents: 10,
            enable_hierarchy: true,
            max_hierarchy_depth: 3,
            knowledge_isolation: Types::IsolationLevel::MODERATE,
            task_timeout: 30_000,
            adaptive_allocation: true,
            conflict_resolution: Types::ConflictResolutionStrategy::WEIGHTED,
            performance_window_size: 100
          }
          super(**defaults.merge(kwargs))
        end
      end

      # Current state of the swarm
      SwarmState = Data.define(
        :swarm_id,
        :status,
        :active_agent_count,
        :active_tasks,
        :completed_tasks_count,
        :failed_tasks_count,
        :metrics,
        :last_updated
      )

      # Assignment of an agent to a task
      AgentAssignment = Data.define(
        :agent_id,
        :task,
        :knowledge_partition,
        :assigned_at,
        :priority
      )

      # Performance metrics for an agent
      AgentPerformance = Data.define(
        :agent_id,
        :task_id,
        :success,
        :response_time,
        :score,
        :timestamp
      )

      # Overall metrics for the swarm
      SwarmMetrics = Data.define(
        :total_agents,
        :average_response_time,
        :success_rate,
        :throughput,
        :resource_utilization,
        :knowledge_distribution_score
      )

      # SwarmCoordinator - Main equipment class that coordinates multiple agents
      # in a swarm configuration with origin-centric provenance tracking.
      class SwarmCoordinator
        attr_reader :config, :origin_id

        # Creates a new SwarmCoordinator instance
        # @param config [Hash] Configuration for the coordinator
        # @param origin_id [String, nil] Origin identifier for provenance tracking
        def initialize(config = {}, origin_id = nil)
          @config = SwarmConfig.new(**config)
          @origin_id = origin_id || generate_origin_id
          @swarm_id = generate_swarm_id

          @orchestrator = AgentOrchestrator.new(
            max_agents: @config.max_agents,
            enable_hierarchy: @config.enable_hierarchy,
            max_hierarchy_depth: @config.max_hierarchy_depth
          )

          @knowledge_manager = AsymmetricKnowledge.new(
            isolation_level: @config.knowledge_isolation
          )

          @task_decomposer = TaskDecomposer.new(
            max_parallelism: @config.max_agents
          )

          @result_aggregator = ResultAggregator.new(
            conflict_resolution: @config.conflict_resolution
          )

          @agents = {}
          @assignments = {}
          @performance_history = {}
          @state = initialize_state
        end

        # Register an agent with the swarm
        # @param agent [Hash] Agent profile to register
        # @return [Boolean] True if registration successful
        def register_agent(agent)
          raise Error, "Maximum agent limit (#{@config.max_agents}) reached" if @agents.size >= @config.max_agents
          raise Error, "Agent #{agent[:id]} is already registered" if @agents.key?(agent[:id])

          profile = AgentOrchestrator::AgentProfile.new(
            id: agent[:id],
            name: agent[:name],
            role: agent[:role],
            capabilities: agent[:capabilities],
            status: agent[:status] || Types::ExecutionStatus::IDLE,
            hierarchy_level: agent[:hierarchy_level] || 0,
            parent_agent_id: agent[:parent_agent_id],
            child_agent_ids: [],
            metadata: agent[:metadata] || {},
            current_load: 0,
            weight: 1.0
          )

          registered = @orchestrator.register_agent(profile)
          return false unless registered

          @agents[profile.id] = profile
          @performance_history[profile.id] = []

          @knowledge_manager.create_partition(profile.id, profile.role)

          update_state
          true
        end

        # Unregister an agent from the swarm
        # @param agent_id [String] Agent identifier to unregister
        # @return [Boolean] True if unregistration successful
        def unregister_agent(agent_id)
          return false unless @agents.key?(agent_id)

          assignment = @assignments[agent_id]
          reassign_task(assignment[:task]) if assignment

          @agents.delete(agent_id)
          @performance_history.delete(agent_id)
          @assignments.delete(agent_id)
          @orchestrator.unregister_agent(agent_id)
          @knowledge_manager.remove_partition(agent_id)

          update_state
          true
        end

        # Execute a task using the swarm
        # @param task [String] Task description
        # @param context [Hash] Execution context
        # @return [Hash] Aggregated result from agents
        def execute_task(task, context = {})
          @state = @state.with(status: Types::ExecutionStatus::RUNNING)
          update_state

          begin
            dependency_graph = @task_decomposer.decompose(task, context)
            results = execute_dependency_graph(dependency_graph)
            aggregated_result = @result_aggregator.aggregate(results)

            if aggregated_result[:conflicts].length > 0
              resolve_conflicts(aggregated_result[:conflicts])
            end

            @state = @state.with(
              status: Types::ExecutionStatus::COMPLETED,
              completed_tasks_count: @state.completed_tasks_count + dependency_graph[:nodes].size
            )
            update_state

            aggregated_result
          rescue => e
            @state = @state.with(
              status: Types::ExecutionStatus::FAILED,
              failed_tasks_count: @state.failed_tasks_count + 1
            )
            update_state
            raise e
          end
        end

        # Get current swarm state
        # @return [SwarmState] Current state
        def get_state
          @state.dup
        end

        # Get agent performance metrics
        # @param agent_id [String, nil] Optional agent ID for specific metrics
        # @return [Array, Hash] Performance metrics
        def get_performance_metrics(agent_id = nil)
          if agent_id
            @performance_history[agent_id] || []
          else
            @performance_history.transform_values(&:itself)
          end
        end

        # Assign a task to the best available agent
        # @param task [Hash] Task to assign
        # @return [AgentAssignment, nil] Agent assignment or nil if no suitable agent
        def assign_task(task)
          available_agents = get_available_agents(task[:required_capabilities])
          return nil if available_agents.empty?

          selected_agent = select_best_agent(available_agents, task)
          knowledge_partition = @knowledge_manager.get_partition(selected_agent.id)

          assignment = AgentAssignment.new(
            agent_id: selected_agent.id,
            task: task,
            knowledge_partition: knowledge_partition,
            assigned_at: DateTime.now,
            priority: task[:priority]
          )

          @assignments[selected_agent.id] = assignment
          update_state

          assignment
        end

        # Update agent performance after task completion
        # @param agent_id [String] Agent identifier
        # @param performance [AgentPerformance] Performance metrics
        def update_agent_performance(agent_id, performance)
          history = @performance_history[agent_id] || []
          history << performance

          if history.length > @config.performance_window_size
            history.shift
          end

          @performance_history[agent_id] = history

          adjust_agent_weight(agent_id, performance[:score]) if @config.adaptive_allocation
        end

        private

        def generate_origin_id
          "origin-#{Time.now.to_i}-#{SecureRandom.alphanumeric(9)}"
        end

        def generate_swarm_id
          "swarm-#{Time.now.to_i}-#{SecureRandom.alphanumeric(9)}"
        end

        def initialize_state
          SwarmState.new(
            swarm_id: @swarm_id,
            status: Types::ExecutionStatus::IDLE,
            active_agent_count: 0,
            active_tasks: [],
            completed_tasks_count: 0,
            failed_tasks_count: 0,
            metrics: calculate_metrics,
            last_updated: DateTime.now
          )
        end

        def update_state
          @state = @state.with(
            active_agent_count: @agents.size,
            metrics: calculate_metrics,
            last_updated: DateTime.now
          )
        end

        def calculate_metrics
          performances = @performance_history.values.flatten

          SwarmMetrics.new(
            total_agents: @agents.size,
            average_response_time: calculate_average(performances.map { |p| p[:response_time] }),
            success_rate: calculate_success_rate(performances),
            throughput: @state.completed_tasks_count,
            resource_utilization: calculate_resource_utilization,
            knowledge_distribution_score: @knowledge_manager.get_distribution_score
          )
        end

        def calculate_average(values)
          return 0 if values.empty?
          values.sum.to_f / values.size
        end

        def calculate_success_rate(performances)
          return 1.0 if performances.empty?
          successful = performances.count { |p| p[:success] }
          successful.to_f / performances.size
        end

        def calculate_resource_utilization
          return 0 if @agents.empty?
          @assignments.size.to_f / @agents.size
        end

        def get_available_agents(required_capabilities)
          @agents.values.select do |agent|
            !@assignments.key?(agent.id) &&
              required_capabilities.all? { |cap| agent.capabilities.include?(cap) }
          end
        end

        def select_best_agent(agents, task)
          return agents.first if !@config.adaptive_allocation || agents.size == 1

          scored_agents = agents.map do |agent|
            history = @performance_history[agent.id] || []
            avg_performance = history.empty? ? 0.5 : calculate_average(history.map { |p| p[:score] })
            specialization_score = calculate_specialization_score(agent, task)

            {
              agent: agent,
              score: avg_performance * 0.6 + specialization_score * 0.4
            }
          end

          scored_agents.sort_by { |sa| -sa[:score] }.first[:agent]
        end

        def calculate_specialization_score(agent, task)
          matching = task[:required_capabilities].count { |cap| agent.capabilities.include?(cap) }
          matching.to_f / task[:required_capabilities].size
        end

        def execute_dependency_graph(graph)
          results = {}
          executing = Set.new
          completed = Set.new

          while completed.size < graph[:nodes].size
            ready_tasks = find_ready_tasks(graph, completed, executing)

            if ready_tasks.empty? && executing.empty?
              raise Error, 'Deadlock detected in dependency graph'
            end

            ready_tasks.each do |task_id|
              executing.add(task_id)
              task = graph[:nodes][task_id]

              begin
                assignment = assign_task(task)
                raise Error, "No available agent for task #{task_id}" unless assignment

                result = execute_assigned_task(assignment)
                results[task_id] = result
                completed.add(task_id)

                update_agent_performance(assignment.agent_id, AgentPerformance.new(
                  agent_id: assignment.agent_id,
                  task_id: task_id,
                  success: true,
                  response_time: ((DateTime.now - assignment.assigned_at) * 86_400_000).to_i,
                  score: 1,
                  timestamp: DateTime.now
                ))
              rescue => e
                completed.add(task_id)
                raise e
              ensure
                executing.delete(task_id)
              end
            end
          end

          results
        end

        def find_ready_tasks(graph, completed, executing)
          ready = []

          graph[:nodes].each do |task_id, task|
            next if completed.include?(task_id) || executing.include?(task_id)

            dependencies = graph[:dependencies][task_id] || []
            all_met = dependencies.all? { |dep| completed.include?(dep) }

            ready << task_id if all_met
          end

          ready
        end

        def execute_assigned_task(assignment)
          sleep 0.1
          {}
        end

        def reassign_task(task)
          new_assignment = assign_task(task)
          @state = @state.with(failed_tasks_count: @state.failed_tasks_count + 1) unless new_assignment
        end

        def resolve_conflicts(conflicts)
          conflicts.each do |conflict|
            case @config.conflict_resolution
            when Types::ConflictResolutionStrategy::VOTING
              resolve_by_voting(conflict)
            when Types::ConflictResolutionStrategy::WEIGHTED
              resolve_by_weight(conflict)
            when Types::ConflictResolutionStrategy::HIERARCHICAL
              resolve_by_hierarchy(conflict)
            when Types::ConflictResolutionStrategy::CONSENSUS
              resolve_by_consensus(conflict)
            end
          end
        end

        def resolve_by_voting(conflict)
          # Simple majority voting
        end

        def resolve_by_weight(conflict)
          # Weight by agent performance
        end

        def resolve_by_hierarchy(conflict)
          # Resolve by agent hierarchy level
        end

        def resolve_by_consensus(conflict)
          # Attempt to find consensus
        end

        def adjust_agent_weight(agent_id, performance_score)
          @orchestrator.adjust_agent_weight(agent_id, performance_score)
        end
      end
    end
  end
end
