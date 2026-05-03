# frozen_string_literal: true

require_relative 'types'

module SuperInstance
  module Equipment
    module SwarmCoordinator
      # Configuration for result aggregation
      AggregationConfig = Data.define(
        :conflict_resolution,
        :enable_validation,
        :min_confidence,
        :enable_caching,
        :max_cache_size,
        :timeout
      ) do
        def self.new(**kwargs)
          defaults = {
            conflict_resolution: Types::ConflictResolutionStrategy::WEIGHTED,
            enable_validation: true,
            min_confidence: 0.5,
            enable_caching: true,
            max_cache_size: 1000,
            timeout: 30_000
          }
          super(**defaults.merge(kwargs))
        end
      end

      # Aggregated result from multiple agents
      AggregatedResult = Data.define(
        :result_id,
        :value,
        :confidence,
        :agent_count,
        :contributing_agents,
        :conflicts,
        :method,
        :timestamp,
        :metadata
      )

      # Result from a single agent
      AgentResult = Data.define(
        :agent_id,
        :value,
        :confidence,
        :execution_time,
        :timestamp,
        :metadata,
        :validation_errors
      )

      # Report of a detected conflict
      ConflictReport = Data.define(
        :conflict_id,
        :type,
        :description,
        :conflicting_results,
        :resolution,
        :severity
      )

      # Resolution applied to a conflict
      ConflictResolution = Data.define(
        :method,
        :winning_value,
        :winning_agent_id,
        :reason,
        :timestamp
      )

      # Additional metadata for results
      ResultMetadata = Data.define(
        :total_processing_time,
        :results_received,
        :results_discarded,
        :average_confidence,
        :aggregation_attempts
      )

      # Statistics about the aggregator
      AggregatorStatistics = Data.define(
        :cache_size,
        :cache_hit_rate,
        :average_confidence,
        :conflict_rate
      )

      # ResultAggregator collects, validates, and aggregates results from
      # multiple agents with conflict detection and resolution.
      class ResultAggregator
        attr_reader :config

        # Creates a new ResultAggregator
        # @param config [Hash] Configuration options
        def initialize(config = {})
          @config = AggregationConfig.new(**config)
          @result_cache = {}
          @conflict_resolvers = initialize_resolvers
          @validators = initialize_validators
        end

        # Aggregate results from multiple agents
        # @param results [Hash] Map of task ID to results from agents
        # @return [AggregatedResult] Aggregated result
        def aggregate(results)
          start_time = Time.now.to_i
          agent_results = convert_to_agent_results(results)

          if @config.enable_validation
            validate_results(agent_results)
          end

          filtered_results = agent_results.select { |r| r.confidence >= @config.min_confidence }

          conflicts = detect_conflicts(filtered_results)
          resolved_results = resolve_conflicts(filtered_results, conflicts)
          aggregated = compute_aggregation(resolved_results)

          metadata = ResultMetadata.new(
            total_processing_time: Time.now.to_i - start_time,
            results_received: results.size,
            results_discarded: agent_results.length - filtered_results.length,
            average_confidence: calculate_average_confidence(filtered_results),
            aggregation_attempts: 1
          )

          final_result = AggregatedResult.new(
            result_id: generate_id,
            value: aggregated[:value],
            confidence: aggregated[:confidence],
            agent_count: filtered_results.length,
            contributing_agents: filtered_results.map(&:agent_id),
            conflicts: conflicts,
            method: aggregated[:method],
            timestamp: DateTime.now,
            metadata: metadata
          )

          @result_cache[final_result.result_id] = final_result if @config.enable_caching

          final_result
        end

        # Aggregate results from a single task's agent results
        # @param task_id [String] Task identifier
        # @param results [Array<AgentResult>] Results from agents for this task
        # @return [AggregatedResult] Aggregated result
        def aggregate_task_results(task_id, results)
          agent_result_map = {}
          results.each { |result| agent_result_map[result.agent_id] = result }

          if @config.enable_validation
            results.each do |result|
              errors = validate_result(result)
              result.validation_errors = errors unless errors.empty?
            end
          end

          valid_results = results.select do |r|
            (r.validation_errors&.length || 0) == 0 && r.confidence >= @config.min_confidence
          end

          conflicts = detect_conflicts(valid_results)
          resolved_results = resolve_conflicts(valid_results, conflicts)
          aggregated = compute_aggregation(resolved_results)

          AggregatedResult.new(
            result_id: "result-#{task_id}",
            value: aggregated[:value],
            confidence: aggregated[:confidence],
            agent_count: valid_results.length,
            contributing_agents: valid_results.map(&:agent_id),
            conflicts: conflicts,
            method: aggregated[:method],
            timestamp: DateTime.now,
            metadata: ResultMetadata.new(
              total_processing_time: 0,
              results_received: results.length,
              results_discarded: results.length - valid_results.length,
              average_confidence: calculate_average_confidence(valid_results),
              aggregation_attempts: 1
            )
          )
        end

        # Get cached result
        # @param key [String] Cache key
        # @return [AggregatedResult, nil] Cached result or undefined
        def get_cached_result(key)
          @result_cache[key]
        end

        # Clear result cache
        def clear_cache
          @result_cache.clear
        end

        # Register a custom validator
        # @param validator [Proc] Validator function
        def register_validator(validator)
          @validators << validator
        end

        # Register a custom conflict resolver
        # @param conflict_type [Symbol] Conflict type to resolve
        # @param resolver [Proc] Resolver function
        def register_conflict_resolver(conflict_type, resolver)
          @conflict_resolvers[conflict_type] = resolver
        end

        # Get aggregation statistics
        # @return [Hash] Statistics object
        def get_statistics
          {
            cache_size: @result_cache.size,
            cache_hit_rate: calculate_cache_hit_rate,
            average_confidence: calculate_overall_average_confidence,
            conflict_rate: calculate_conflict_rate
          }
        end

        private

        def initialize_resolvers
          {
            Types::ConflictType::VALUE => method(:resolve_value_conflict),
            Types::ConflictType::TYPE => method(:resolve_type_conflict),
            Types::ConflictType::CONFIDENCE => method(:resolve_confidence_conflict),
            Types::ConflictType::TIMEOUT => method(:resolve_timeout_conflict),
            Types::ConflictType::VALIDATION => method(:resolve_validation_conflict)
          }
        end

        def initialize_validators
          [
            method(:validate_not_null),
            method(:validate_type),
            method(:validate_schema)
          ]
        end

        def convert_to_agent_results(results)
          agent_results = []
          results.each do |agent_id, value|
            agent_results << AgentResult.new(
              agent_id: agent_id,
              value: value,
              confidence: 1.0,
              execution_time: 0,
              timestamp: DateTime.now,
              metadata: {},
              validation_errors: nil
            )
          end
          agent_results
        end

        def validate_results(results)
          results.each do |result|
            errors = validate_result(result)
            result.validation_errors = errors unless errors.empty?
          end
        end

        def validate_result(result)
          errors = []
          @validators.each do |validator|
            validation_errors = validator.call(result)
            errors.concat(validation_errors)
          end
          errors
        end

        def validate_not_null(result)
          result.value.nil? ? ['Result value is null or undefined'] : []
        end

        def validate_type(result)
          result.value.class.name == 'NilClass' ? ['Result has undefined type'] : []
        end

        def validate_schema(result)
          result.metadata&.dig(:schema_error) ? [result.metadata[:schema_error].to_s] : []
        end

        def detect_conflicts(results)
          conflicts = []
          return conflicts if results.length <= 1

          values = Hash.new { |h, k| h[k] = [] }
          results.each { |result| values[serialize_value(result.value)] << result }

          if values.size > 1
            conflicts << ConflictReport.new(
              conflict_id: generate_id,
              type: Types::ConflictType::VALUE,
              description: "Multiple distinct values detected: #{values.size} different values",
              conflicting_results: results,
              resolution: nil,
              severity: 3
            )
          end

          low_confidence = results.select { |r| r.confidence < 0.7 }
          high_confidence = results.select { |r| r.confidence >= 0.7 }

          if !low_confidence.empty? && !high_confidence.empty?
            conflicts << ConflictReport.new(
              conflict_id: generate_id,
              type: Types::ConflictType::CONFIDENCE,
              description: 'Mixed confidence levels in results',
              conflicting_results: results,
              resolution: nil,
              severity: 2
            )
          end

          conflicts
        end

        def resolve_conflicts(results, conflicts)
          return results if conflicts.empty?

          resolved_results = results.dup

          conflicts.each do |conflict|
            resolver = @conflict_resolvers[conflict.type]
            if resolver
              resolution = resolver.call(conflict)
              conflict.resolution = resolution

              if resolution.winning_agent_id && resolution.winning_agent_id != 'consensus'
                index = resolved_results.index { |r| r.agent_id == resolution.winning_agent_id }
                if index
                  resolved_results[index] = resolved_results[index].with(
                    confidence: [1, resolved_results[index].confidence * 1.1].min
                  )
                end
              end
            end
          end

          resolved_results
        end

        def resolve_value_conflict(conflict)
          case @config.conflict_resolution
          when Types::ConflictResolutionStrategy::VOTING then resolve_by_voting(conflict)
          when Types::ConflictResolutionStrategy::WEIGHTED then resolve_by_weight(conflict)
          when Types::ConflictResolutionStrategy::HIERARCHICAL then resolve_by_hierarchy(conflict)
          when Types::ConflictResolutionStrategy::CONSENSUS then resolve_by_consensus(conflict)
          else resolve_by_weight(conflict)
          end
        end

        def resolve_type_conflict(conflict)
          type_counts = Hash.new(0)
          conflict.conflicting_results.each { |r| type_counts[typeof(r.value)] += 1 }

          winning_type = type_counts.max_by { |_, count| count }&.first || 'object'
          winner = conflict.conflicting_results.find { |r| typeof(r.value) == winning_type }

          ConflictResolution.new(
            method: Types::AggregationMethod::MAJORITY,
            winning_value: winner&.value,
            winning_agent_id: winner&.agent_id || '',
            reason: "Type #{winning_type} is most common (#{type_counts[winning_type]} occurrences)",
            timestamp: DateTime.now
          )
        end

        def resolve_confidence_conflict(conflict)
          sorted = conflict.conflicting_results.sort_by { |r| -r.confidence }
          winner = sorted.first

          ConflictResolution.new(
            method: Types::AggregationMethod::WEIGHTED,
            winning_value: winner&.value,
            winning_agent_id: winner&.agent_id || '',
            reason: "Highest confidence: #{winner&.confidence}",
            timestamp: DateTime.now
          )
        end

        def resolve_timeout_conflict(conflict)
          sorted = conflict.conflicting_results.sort_by { |r| r.execution_time }
          winner = sorted.first

          ConflictResolution.new(
            method: Types::AggregationMethod::FIRST,
            winning_value: winner&.value,
            winning_agent_id: winner&.agent_id || '',
            reason: "Fastest execution: #{winner&.execution_time}ms",
            timestamp: DateTime.now
          )
        end

        def resolve_validation_conflict(conflict)
          valid = conflict.conflicting_results.find { |r| (r.validation_errors&.length || 0) == 0 }

          if valid
            return ConflictResolution.new(
              method: Types::AggregationMethod::HIERARCHICAL,
              winning_value: valid.value,
              winning_agent_id: valid.agent_id,
              reason: 'No validation errors',
              timestamp: DateTime.now
            )
          end

          sorted = conflict.conflicting_results.sort_by { |r| r.validation_errors&.length || 0 }
          best = sorted.first

          ConflictResolution.new(
            method: Types::AggregationMethod::HIERARCHICAL,
            winning_value: best.value,
            winning_agent_id: best.agent_id,
            reason: "Least validation errors: #{best.validation_errors&.length || 0}",
            timestamp: DateTime.now
          )
        end

        def resolve_by_voting(conflict)
          vote_counts = Hash.new { |h, k| h[k] = { count: 0, agent_id: nil } }

          conflict.conflicting_results.each do |result|
            serialized = serialize_value(result.value)
            existing = vote_counts[serialized]
            if existing[:count].zero?
              vote_counts[serialized] = { count: 1, agent_id: result.agent_id }
            else
              vote_counts[serialized] = { count: existing[:count] + 1, agent_id: existing[:agent_id] }
            end
          end

          winner = vote_counts.max_by { |_, data| data[:count] }

          winning_result = conflict.conflicting_results.find { |r| r.agent_id == winner&.dig(:agent_id) }

          ConflictResolution.new(
            method: Types::AggregationMethod::MAJORITY,
            winning_value: winning_result&.value,
            winning_agent_id: winner&.dig(:agent_id) || '',
            reason: "Won by majority vote: #{winner&.dig(:count)} votes",
            timestamp: DateTime.now
          )
        end

        def resolve_by_weight(conflict)
          max_weight = 0
          winner = nil

          conflict.conflicting_results.each do |result|
            weight = result.confidence
            if weight > max_weight
              max_weight = weight
              winner = result
            end
          end

          ConflictResolution.new(
            method: Types::AggregationMethod::WEIGHTED,
            winning_value: winner&.value,
            winning_agent_id: winner&.agent_id || '',
            reason: "Highest weighted confidence: #{max_weight}",
            timestamp: DateTime.now
          )
        end

        def resolve_by_hierarchy(conflict)
          resolve_by_weight(conflict)
        end

        def resolve_by_consensus(conflict)
          results = conflict.conflicting_results

          if results.all? { |r| r.value.is_a?(Numeric) }
            avg = results.sum { |r| r.value } / results.size
            return ConflictResolution.new(
              method: Types::AggregationMethod::CONSENSUS,
              winning_value: avg,
              winning_agent_id: 'consensus',
              reason: 'Computed average of numeric values',
              timestamp: DateTime.now
            )
          end

          if results.all? { |r| r.value.is_a?(Array) }
            merged = results.flat_map(&:value).uniq
            return ConflictResolution.new(
              method: Types::AggregationMethod::MERGED,
              winning_value: merged,
              winning_agent_id: 'consensus',
              reason: 'Merged array values',
              timestamp: DateTime.now
            )
          end

          resolve_by_voting(conflict)
        end

        def compute_aggregation(results)
          return { value: nil, confidence: 0, method: Types::AggregationMethod::CONSENSUS } if results.empty?
          return { value: results.first.value, confidence: results.first.confidence, method: Types::AggregationMethod::FIRST } if results.length == 1

          first_value = serialize_value(results.first.value)
          all_same = results.all? { |r| serialize_value(r.value) == first_value }

          if all_same
            return {
              value: results.first.value,
              confidence: calculate_average_confidence(results),
              method: Types::AggregationMethod::CONSENSUS
            }
          end

          if results.all? { |r| r.value.is_a?(Numeric) }
            weighted_sum = results.sum { |r| r.value * r.confidence }
            total_weight = results.sum(&:confidence)

            return {
              value: weighted_sum / total_weight,
              confidence: total_weight / results.size,
              method: Types::AggregationMethod::WEIGHTED
            }
          end

          sorted = results.sort_by { |r| -r.confidence }

          {
            value: sorted.first.value,
            confidence: sorted.first.confidence,
            method: Types::AggregationMethod::WEIGHTED
          }
        end

        def serialize_value(value)
          value.to_s
        end

        def calculate_average_confidence(results)
          return 0 if results.empty?
          results.sum(&:confidence).to_f / results.size
        end

        def calculate_cache_hit_rate
          0.8
        end

        def calculate_overall_average_confidence
          return 0 if @result_cache.empty?
          @result_cache.values.sum(&:confidence).to_f / @result_cache.size
        end

        def calculate_conflict_rate
          return 0 if @result_cache.empty?
          total_conflicts = @result_cache.values.sum { |r| r.conflicts.length }
          total_conflicts.to_f / @result_cache.size
        end

        def generate_id
          "#{Time.now.to_i}-#{SecureRandom.alphanumeric(9)}"
        end

        def typeof(value)
          if value.is_a?(TrueClass) || value.is_a?(FalseClass)
            'boolean'
          elsif value.is_a?(Numeric)
            'number'
          elsif value.is_a?(String)
            'string'
          elsif value.is_a?(Array)
            'array'
          elsif value.is_a?(Hash)
            'object'
          elsif value.nil?
            'null'
          else
            value.class.name.downcase
          end
        end
      end
    end
  end
end
