# frozen_string_literal: true

require_relative 'types'

module SuperInstance
  module Equipment
    module SwarmCoordinator
      # Configuration for task decomposition
      DecompositionConfig = Data.define(
        :max_parallelism,
        :min_task_size,
        :max_depth,
        :auto_dependency_detection,
        :default_timeout
      ) do
        def self.new(**kwargs)
          defaults = {
            max_parallelism: 10,
            min_task_size: 0.1,
            max_depth: 5,
            auto_dependency_detection: true,
            default_timeout: 60_000
          }
          super(**defaults.merge(kwargs))
        end
      end

      # A node in the task tree
      TaskNode = Data.define(
        :task_id,
        :description,
        :type,
        :priority,
        :required_capabilities,
        :input,
        :output,
        :status,
        :children,
        :parent_id,
        :estimated_complexity,
        :actual_complexity,
        :estimated_duration,
        :actual_duration,
        :created_at,
        :started_at,
        :completed_at,
        :retry_count,
        :max_retries
      )

      # Dependency graph structure
      DependencyGraph = Data.define(
        :graph_id,
        :nodes,
        :dependencies,
        :dependents,
        :layers,
        :root_task_id,
        :created_at
      )

      # Analysis result for a task
      TaskAnalysis = Data.define(
        :type,
        :complexity,
        :required_capabilities,
        :can_decompose,
        :suggested_strategy,
        :estimated_duration,
        :dependencies
      )

      # Task template for reusable task patterns
      TaskTemplate = Data.define(
        :name,
        :description_template,
        :type,
        :base_complexity,
        :required_capabilities,
        :can_decompose,
        :strategy,
        :estimated_duration
      )

      # Statistics about a dependency graph
      GraphStatistics = Data.define(
        :total_tasks,
        :by_status,
        :by_type,
        :by_priority,
        :max_depth,
        :critical_path,
        :parallelism_factor
      )

      # TaskDecomposer analyzes and decomposes complex tasks into manageable subtasks.
      class TaskDecomposer
        attr_reader :config

        # Creates a new TaskDecomposer
        # @param config [Hash] Configuration options
        def initialize(config = {})
          @config = DecompositionConfig.new(**config)
          @decomposition_strategies = initialize_strategies
          @task_templates = {}
        end

        # Decompose a task into a dependency graph
        # @param task [String] Task description
        # @param context [Hash] Execution context
        # @return [DependencyGraph] Dependency graph
        def decompose(task, context = {})
          analysis = analyze_task(task, context)
          root_task = create_task_node(task, analysis, nil)

          graph = DependencyGraph.new(
            graph_id: generate_id,
            nodes: { root_task.task_id => root_task },
            dependencies: { root_task.task_id => [] },
            dependents: { root_task.task_id => [] },
            layers: [],
            root_task_id: root_task.task_id,
            created_at: DateTime.now
          )

          if analysis.can_decompose && analysis.complexity > @config.min_task_size
            decompose_recursive(root_task, graph, context, 0)
          end

          graph.layers = calculate_layers(graph)
          graph
        end

        # Analyze a task to determine decomposition potential
        # @param task [String] Task description
        # @param context [Hash] Execution context
        # @return [TaskAnalysis] Task analysis
        def analyze_task(task, context = {})
          type = identify_task_type(task, context)
          complexity = estimate_complexity(task, context)
          capabilities = identify_required_capabilities(task, type)
          can_decompose = can_decompose(task, type, complexity)
          strategy = select_strategy(type, complexity)

          TaskAnalysis.new(
            type: type,
            complexity: complexity,
            required_capabilities: capabilities,
            can_decompose: can_decompose,
            suggested_strategy: strategy,
            estimated_duration: estimate_duration(complexity, type),
            dependencies: detect_dependencies(task, context)
          )
        end

        # Get a task by ID from a graph
        # @param graph [DependencyGraph] Dependency graph
        # @param task_id [String] Task identifier
        # @return [TaskNode, nil] Task node or undefined
        def get_task(graph, task_id)
          graph.nodes[task_id]
        end

        # Get tasks ready for execution
        # @param graph [DependencyGraph] Dependency graph
        # @param completed [Set<String>] Set of completed task IDs
        # @return [Array<TaskNode>] Tasks ready to execute
        def get_ready_tasks(graph, completed)
          ready = []

          graph.nodes.each do |task_id, task|
            next if completed.include?(task_id) || task.status != Types::ExecutionStatus::IDLE

            deps = graph.dependencies[task_id] || []
            all_deps_met = deps.all? { |dep| completed.include?(dep) }

            ready << task if all_deps_met
          end

          ready.sort_by { |t| -get_priority_value(t.priority) }
        end

        # Add a dependency between tasks
        # @param graph [DependencyGraph] Dependency graph
        # @param task_id [String] Task ID
        # @param depends_on [String] Task it depends on
        def add_dependency(graph, task_id, depends_on)
          unless graph.nodes.key?(task_id) && graph.nodes.key?(depends_on)
            raise Error, 'Both tasks must exist in the graph'
          end

          deps = graph.dependencies[task_id] || []
          deps << depends_on unless deps.include?(depends_on)
          graph.dependencies[task_id] = deps

          dependents = graph.dependents[depends_on] || []
          dependents << task_id unless dependents.include?(task_id)
          graph.dependents[depends_on] = dependents

          graph.layers = calculate_layers(graph)
        end

        # Remove a dependency
        # @param graph [DependencyGraph] Dependency graph
        # @param task_id [String] Task ID
        # @param depends_on [String] Task to remove dependency on
        def remove_dependency(graph, task_id, depends_on)
          deps = graph.dependencies[task_id] || []
          dep_index = deps.index(depends_on)
          if dep_index
            deps.delete_at(dep_index)
            graph.dependencies[task_id] = deps
          end

          dependents = graph.dependents[depends_on] || []
          dependent_index = dependents.index(task_id)
          if dependent_index
            dependents.delete_at(dependent_index)
            graph.dependents[depends_on] = dependents
          end

          graph.layers = calculate_layers(graph)
        end

        # Update task status
        # @param graph [DependencyGraph] Dependency graph
        # @param task_id [String] Task identifier
        # @param status [Symbol] New status
        def update_task_status(graph, task_id, status)
          task = graph.nodes[task_id]
          return unless task

          updated_task = if status == Types::ExecutionStatus::RUNNING && !task.started_at
            task.with(started_at: DateTime.now, status: status)
          elsif [:completed, :failed].include?(status)
            completed_at = DateTime.now
            actual_duration = task.started_at ? ((completed_at - task.started_at) * 86_400_000).to_i : nil
            task.with(completed_at: completed_at, actual_duration: actual_duration, status: status)
          else
            task.with(status: status)
          end

          graph.nodes[task_id] = updated_task
        end

        # Get task statistics
        # @param graph [DependencyGraph] Dependency graph
        # @return [Hash] Statistics object
        def get_statistics(graph)
          nodes = graph.nodes.values

          GraphStatistics.new(
            total_tasks: nodes.size,
            by_status: group_by_status(nodes),
            by_type: group_by_type(nodes),
            by_priority: group_by_priority(nodes),
            max_depth: graph.layers.size,
            critical_path: find_critical_path(graph),
            parallelism_factor: calculate_parallelism_factor(graph)
          )
        end

        # Register a task template
        # @param name [String] Template name
        # @param template [TaskTemplate] Task template
        def register_template(name, template)
          @task_templates[name] = template
        end

        # Create task from template
        # @param template_name [String] Template name
        # @param params [Hash] Template parameters
        # @return [TaskNode, nil] Task node
        def from_template(template_name, params)
          template = @task_templates[template_name]
          return nil unless template

          description = interpolate_template(template.description_template, params)
          analysis = TaskAnalysis.new(
            type: template.type,
            complexity: template.base_complexity,
            required_capabilities: template.required_capabilities,
            can_decompose: template.can_decompose,
            suggested_strategy: template.strategy,
            estimated_duration: template.estimated_duration,
            dependencies: []
          )

          create_task_node(description, analysis, nil)
        end

        private

        def initialize_strategies
          {
            Types::TaskType::COMPUTATION => Types::DecompositionStrategy::DIVIDE_CONQUER,
            Types::TaskType::IO => Types::DecompositionStrategy::PARALLEL,
            Types::TaskType::COMMUNICATION => Types::DecompositionStrategy::PIPELINE,
            Types::TaskType::DECISION => Types::DecompositionStrategy::SEQUENTIAL,
            Types::TaskType::VALIDATION => Types::DecompositionStrategy::PARALLEL,
            Types::TaskType::AGGREGATION => Types::DecompositionStrategy::MAP_REDUCE,
            Types::TaskType::DECOMPOSITION => Types::DecompositionStrategy::DIVIDE_CONQUER,
            Types::TaskType::SYNCHRONIZATION => Types::DecompositionStrategy::SEQUENTIAL
          }
        end

        def create_task_node(description, analysis, parent_id)
          TaskNode.new(
            task_id: generate_id,
            description: description,
            type: analysis.type,
            priority: Types::TaskPriority::NORMAL,
            required_capabilities: analysis.required_capabilities,
            input: {},
            output: nil,
            status: Types::ExecutionStatus::IDLE,
            children: [],
            parent_id: parent_id,
            estimated_complexity: analysis.complexity,
            actual_complexity: nil,
            estimated_duration: analysis.estimated_duration,
            actual_duration: nil,
            created_at: DateTime.now,
            started_at: nil,
            completed_at: nil,
            retry_count: 0,
            max_retries: 3
          )
        end

        def decompose_recursive(task, graph, context, depth)
          return if depth >= @config.max_depth

          analysis = analyze_task(task.description, context)

          return unless analysis.can_decompose

          subtasks = generate_subtasks(task, analysis, context)

          subtasks.each do |subtask|
            subtask = subtask.with(parent_id: task.task_id)
            task.children << subtask.task_id

            graph.nodes[subtask.task_id] = subtask
            graph.dependencies[subtask.task_id] = [task.task_id]
            graph.dependents[subtask.task_id] = []

            task_dependents = graph.dependents[task.task_id] || []
            task_dependents << subtask.task_id
            graph.dependents[task.task_id] = task_dependents

            decompose_recursive(subtask, graph, context, depth + 1)
          end
        end

        def generate_subtasks(task, analysis, context)
          subtasks = []
          strategy = analysis.suggested_strategy

          case strategy
          when Types::DecompositionStrategy::PARALLEL
            3.times do |i|
              complexity_ratio = analysis.complexity / 3.0
              subtask = create_task_node(
                "#{task.description} (part #{i + 1})",
                analysis.with(complexity: complexity_ratio),
                task.task_id
              )
              subtasks << subtask
            end

          when Types::DecompositionStrategy::SEQUENTIAL
            stages = [:prepare, :execute, :finalize]
            stages.each_with_index do |stage, i|
              complexity_ratio = analysis.complexity / 3.0
              subtask = create_task_node(
                "#{task.description} - #{stage}",
                analysis.with(complexity: complexity_ratio),
                task.task_id
              )
              subtask = subtask.with(priority: i == 0 ? Types::TaskPriority::HIGH : Types::TaskPriority::NORMAL)
              subtask = subtask.with(input: { previous_task_id: subtasks[i - 1].task_id }) if i > 0
              subtasks << subtask
            end

          when Types::DecompositionStrategy::PIPELINE
            pipeline_stages = [:input, :process, :output]
            pipeline_stages.each do |stage|
              complexity_ratio = analysis.complexity / 3.0
              type = stage == :input || stage == :output ? Types::TaskType::IO : Types::TaskType::COMPUTATION
              subtask = create_task_node(
                "#{task.description} - #{stage} stage",
                analysis.with(complexity: complexity_ratio, type: type),
                task.task_id
              )
              subtasks << subtask
            end

          when Types::DecompositionStrategy::MAP_REDUCE
            map_task = create_task_node(
              "#{task.description} - map",
              analysis.with(complexity: analysis.complexity * 0.6, type: Types::TaskType::COMPUTATION),
              task.task_id
            )
            reduce_task = create_task_node(
              "#{task.description} - reduce",
              analysis.with(complexity: analysis.complexity * 0.4, type: Types::TaskType::AGGREGATION),
              task.task_id
            )
            subtasks << map_task << reduce_task

          when Types::DecompositionStrategy::DIVIDE_CONQUER
            divide_task = create_task_node(
              "#{task.description} - divide",
              analysis.with(complexity: analysis.complexity * 0.2, type: Types::TaskType::DECOMPOSITION),
              task.task_id
            )
            solve_task = create_task_node(
              "#{task.description} - solve",
              analysis.with(complexity: analysis.complexity * 0.6, type: Types::TaskType::COMPUTATION),
              task.task_id
            )
            combine_task = create_task_node(
              "#{task.description} - combine",
              analysis.with(complexity: analysis.complexity * 0.2, type: Types::TaskType::AGGREGATION),
              task.task_id
            )
            subtasks << divide_task << solve_task << combine_task
          end

          subtasks
        end

        def calculate_layers(graph)
          layers = []
          assigned = Set.new

          while assigned.size < graph.nodes.size
            layer = []

            graph.nodes.each do |task_id|
              next if assigned.include?(task_id)

              deps = graph.dependencies[task_id] || []
              all_deps_assigned = deps.all? { |dep| assigned.include?(dep) }

              layer << task_id if all_deps_assigned
            end

            if layer.empty?
              graph.nodes.each do |task_id|
                layer << task_id unless assigned.include?(task_id)
              end
            end

            layers << layer
            layer.each { |id| assigned.add(id) }
          end

          layers
        end

        def identify_task_type(task, context)
          lower_task = task.downcase

          return Types::TaskType::COMPUTATION if lower_task.match?(/compute|calculate|process/)
          return Types::TaskType::IO if lower_task.match?(/read|write|fetch/)
          return Types::TaskType::COMMUNICATION if lower_task.match?(/send|receive|communicate/)
          return Types::TaskType::DECISION if lower_task.match?(/decide|choose|select/)
          return Types::TaskType::VALIDATION if lower_task.match?(/validate|check|verify/)
          return Types::TaskType::AGGREGATION if lower_task.match?(/aggregate|merge|combine/)
          return Types::TaskType::SYNCHRONIZATION if lower_task.match?(/sync|wait|barrier/)

          Types::TaskType::COMPUTATION
        end

        def estimate_complexity(task, context)
          complexity = [task.length / 200.0, 1.0].min

          complexity_indicators = %w[complex multiple parallel hierarchical recursive nested]
          complexity_indicators.each do |indicator|
            complexity = [complexity + 0.15, 1.0].min if task.downcase.include?(indicator)
          end

          complexity
        end

        def identify_required_capabilities(task, type)
          capabilities = []
          lower_task = task.downcase

          capabilities << 'data_processing' if lower_task.match?(/data|database/)
          capabilities << 'network' if lower_task.match?(/api|http/)
          capabilities << 'filesystem' if lower_task.match?(/file|disk/)
          capabilities << 'computation' if lower_task.match?(/compute|calculate/)
          capabilities << 'validation' if lower_task.match?(/validate|verify/)

          capabilities.empty? ? ['general'] : capabilities
        end

        def can_decompose(task, type, complexity)
          return false if complexity < @config.min_task_size

          atomic_indicators = %w[simple atomic single basic]
          !atomic_indicators.any? { |ind| task.downcase.include?(ind) }
        end

        def select_strategy(type, complexity)
          @decomposition_strategies[type] || Types::DecompositionStrategy::PARALLEL
        end

        def estimate_duration(complexity, type)
          (1000 + complexity * 10_000).to_i
        end

        def detect_dependencies(task, context)
          deps = []
          deps << 'previous' if task.include?('after') || task.include?('then')
          deps
        end

        def get_priority_value(priority)
          case priority
          when Types::TaskPriority::CRITICAL then 4
          when Types::TaskPriority::HIGH then 3
          when Types::TaskPriority::NORMAL then 2
          when Types::TaskPriority::LOW then 1
          else 2
          end
        end

        def group_by_status(nodes)
          {
            Types::ExecutionStatus::IDLE => nodes.count { |n| n.status == Types::ExecutionStatus::IDLE },
            Types::ExecutionStatus::RUNNING => nodes.count { |n| n.status == Types::ExecutionStatus::RUNNING },
            Types::ExecutionStatus::PAUSED => nodes.count { |n| n.status == Types::ExecutionStatus::PAUSED },
            Types::ExecutionStatus::COMPLETED => nodes.count { |n| n.status == Types::ExecutionStatus::COMPLETED },
            Types::ExecutionStatus::FAILED => nodes.count { |n| n.status == Types::ExecutionStatus::FAILED }
          }
        end

        def group_by_type(nodes)
          counts = Hash.new(0)
          nodes.each { |n| counts[n.type] += 1 }
          counts
        end

        def group_by_priority(nodes)
          {
            Types::TaskPriority::CRITICAL => nodes.count { |n| n.priority == Types::TaskPriority::CRITICAL },
            Types::TaskPriority::HIGH => nodes.count { |n| n.priority == Types::TaskPriority::HIGH },
            Types::TaskPriority::NORMAL => nodes.count { |n| n.priority == Types::TaskPriority::NORMAL },
            Types::TaskPriority::LOW => nodes.count { |n| n.priority == Types::TaskPriority::LOW }
          }
        end

        def find_critical_path(graph)
          path = []
          visited = Set.new

          dfs = lambda { |task_id, current_path|
            return current_path if visited.include?(task_id)

            visited.add(task_id)
            current_path = current_path.dup
            current_path << task_id

            dependents = graph.dependents[task_id] || []
            longest_path = current_path

            dependents.each do |dependent|
              result = dfs.call(dependent, current_path)
              longest_path = result if result.length > longest_path.length
            end

            longest_path
          }

          dfs.call(graph.root_task_id, path)
        end

        def calculate_parallelism_factor(graph)
          return 1 if graph.layers.empty?

          avg_layer_size = graph.nodes.size.to_f / graph.layers.size
          [@config.max_parallelism, avg_layer_size].min.to_f
        end

        def interpolate_template(template, params)
          template.gsub(/\{\{(\w+)\}\}/) { |_m| params[$1.to_sym]&.to_s || "{{#{$1}}}" }
        end

        def generate_id
          "task-#{Time.now.to_i}-#{SecureRandom.alphanumeric(9)}"
        end
      end
    end
  end
end
