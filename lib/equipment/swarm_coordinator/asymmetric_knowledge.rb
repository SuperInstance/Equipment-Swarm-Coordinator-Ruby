# frozen_string_literal: true

require_relative 'types'

module SuperInstance
  module Equipment
    module SwarmCoordinator
      # Configuration for knowledge management
      KnowledgeConfig = Data.define(
        :isolation_level,
        :enable_caching,
        :max_partition_size,
        :retention_period,
        :enable_provenance
      ) do
        def self.new(**kwargs)
          defaults = {
            isolation_level: Types::IsolationLevel::MODERATE,
            enable_caching: true,
            max_partition_size: 10_000,
            retention_period: 86_400_000,
            enable_provenance: true
          }
          super(**defaults.merge(kwargs))
        end
      end

      # A partition of knowledge for a specific agent
      KnowledgePartition = Data.define(
        :partition_id,
        :agent_id,
        :entries,
        :access_level,
        :created_at,
        :updated_at,
        :provenance
      )

      # A single knowledge entry
      KnowledgeEntry = Data.define(
        :id,
        :key,
        :value,
        :level,
        :source,
        :confidence,
        :created_at,
        :expires_at,
        :tags
      )

      # Policy for knowledge access
      AccessPolicy = Data.define(
        :policy_id,
        :source_agent_id,
        :target_agent_id,
        :allowed_keys,
        :denied_keys,
        :granted_level,
        :expires_at,
        :conditions
      )

      # Condition for access policy
      AccessCondition = Data.define(
        :type,
        :operator,
        :value
      )

      # Provenance information for knowledge
      KnowledgeProvenance = Data.define(
        :origin_id,
        :source_agent,
        :transformation,
        :timestamp
      )

      # Summary of knowledge for an agent
      KnowledgeSummary = Data.define(
        :agent_id,
        :entry_count,
        :categories,
        :last_updated,
        :provenance_depth
      )

      # Internal knowledge graph for tracking relationships
      class KnowledgeGraph
        def initialize
          @nodes = {}
          @edges = {}
        end

        def add_node(key, entry)
          @nodes[key] = entry
          @edges[key] ||= Set.new
        end

        def add_edge(from, to)
          @edges[from]&.add(to)
        end

        def get_related(key)
          @edges[key]&.to_a || []
        end
      end

      # AsymmetricKnowledge manages the distribution of knowledge across agents
      # ensuring each agent only has access to what they need.
      class AsymmetricKnowledge
        attr_reader :config

        # Creates a new AsymmetricKnowledge manager
        # @param config [Hash] Configuration options
        def initialize(config = {})
          @config = KnowledgeConfig.new(**config)
          @partitions = {}
          @access_policies = {}
          @global_knowledge = {}
          @knowledge_graph = KnowledgeGraph.new
        end

        # Create a knowledge partition for an agent
        # @param agent_id [String] Agent identifier
        # @param role [Symbol] Agent role
        # @return [KnowledgePartition] Created partition
        def create_partition(agent_id, role)
          raise Error, "Partition already exists for agent #{agent_id}" if @partitions.key?(agent_id)

          access_level = determine_access_level(role)

          partition = KnowledgePartition.new(
            partition_id: "partition-#{agent_id}",
            agent_id: agent_id,
            entries: {},
            access_level: access_level,
            created_at: DateTime.now,
            updated_at: DateTime.now,
            provenance: []
          )

          @partitions[agent_id] = partition
          partition
        end

        # Remove a knowledge partition
        # @param agent_id [String] Agent identifier
        # @return [Boolean] True if removed successfully
        def remove_partition(agent_id)
          return false unless @partitions.key?(agent_id)

          @partitions.delete(agent_id)
          @access_policies.delete(agent_id)
          true
        end

        # Get a knowledge partition
        # @param agent_id [String] Agent identifier
        # @return [KnowledgePartition, nil] Partition or undefined
        def get_partition(agent_id)
          @partitions[agent_id]
        end

        # Add knowledge to global store
        # @param entry [Hash] Knowledge entry
        # @return [String] Entry ID
        def add_global_knowledge(entry)
          id = generate_id

          full_entry = KnowledgeEntry.new(
            id: id,
            key: entry[:key],
            value: entry[:value],
            level: entry[:level] || Types::KnowledgeLevel::PARTIAL,
            source: entry[:source],
            confidence: entry[:confidence] || 1.0,
            created_at: DateTime.now,
            expires_at: entry[:expires_at],
            tags: entry[:tags] || []
          )

          @global_knowledge[entry[:key]] = full_entry
          @knowledge_graph.add_node(entry[:key], full_entry)

          id
        end

        # Distribute knowledge to an agent
        # @param agent_id [String] Target agent ID
        # @param key [String] Knowledge key
        # @param value [Object] Knowledge value
        # @param source [String] Source identifier
        # @return [Boolean] True if distributed successfully
        def distribute_knowledge(agent_id, key, value, source)
          partition = @partitions[agent_id]
          return false unless partition

          return false unless can_access(agent_id, key)

          entry_id = generate_id
          entry = KnowledgeEntry.new(
            id: entry_id,
            key: key,
            value: value,
            level: partition.access_level,
            source: source,
            confidence: 1.0,
            created_at: DateTime.now,
            expires_at: nil,
            tags: []
          )

          partition.entries[key] = entry
          partition = partition.with(updated_at: DateTime.now)

          if @config.enable_provenance
            provenance = KnowledgeProvenance.new(
              origin_id: generate_origin_id,
              source_agent: source,
              transformation: nil,
              timestamp: DateTime.now
            )
            partition = partition.with(provenance: partition.provenance + [provenance])
          end

          @partitions[agent_id] = partition
          true
        end

        # Request knowledge from another agent
        # @param requesting_agent_id [String] Agent requesting knowledge
        # @param target_agent_id [String] Agent to request from
        # @param key [String] Knowledge key to request
        # @return [KnowledgeEntry, nil] Requested knowledge or null
        def request_knowledge(requesting_agent_id, target_agent_id, key)
          policies = @access_policies[requesting_agent_id] || []
          has_policy = policies.any? do |p|
            p.source_agent_id == target_agent_id &&
              matches_pattern(key, p.allowed_keys) &&
              !matches_pattern(key, p.denied_keys)
          end

          if !has_policy && @config.isolation_level == Types::IsolationLevel::STRICT
            return nil
          end

          target_partition = @partitions[target_agent_id]
          return nil unless target_partition

          entry = target_partition.entries[key]
          return nil unless entry

          return nil unless can_share(entry, requesting_agent_id)

          distribute_knowledge(requesting_agent_id, key, entry.value, target_agent_id)

          entry
        end

        # Check if an agent can access specific knowledge
        # @param agent_id [String] Agent identifier
        # @param key [String] Knowledge key
        # @return [Boolean] True if access allowed
        def can_access(agent_id, key)
          partition = @partitions[agent_id]
          return false unless partition

          case @config.isolation_level
          when Types::IsolationLevel::STRICT
            check_strict_access(agent_id, key)
          when Types::IsolationLevel::MODERATE
            check_moderate_access(agent_id, key)
          when Types::IsolationLevel::RELAXED
            true
          end
        end

        # Set access policy between agents
        # @param policy [Hash] Access policy to set
        # @return [String] Policy ID
        def set_access_policy(policy)
          policy_id = generate_id

          full_policy = AccessPolicy.new(
            policy_id: policy_id,
            source_agent_id: policy[:source_agent_id],
            target_agent_id: policy[:target_agent_id],
            allowed_keys: policy[:allowed_keys] || [],
            denied_keys: policy[:denied_keys] || [],
            granted_level: policy[:granted_level] || Types::KnowledgeLevel::PARTIAL,
            expires_at: policy[:expires_at],
            conditions: policy[:conditions] || []
          )

          existing_policies = @access_policies[policy[:target_agent_id]] || []
          existing_policies << full_policy
          @access_policies[policy[:target_agent_id]] = existing_policies

          policy_id
        end

        # Revoke access policy
        # @param target_agent_id [String] Target agent ID
        # @param policy_id [String] Policy ID to revoke
        # @return [Boolean] True if revoked successfully
        def revoke_access_policy(target_agent_id, policy_id)
          policies = @access_policies[target_agent_id]
          return false unless policies

          index = policies.index { |p| p.policy_id == policy_id }
          return false unless index

          policies.delete_at(index)
          true
        end

        # Get knowledge distribution score
        # @return [Float] Distribution score (0-1)
        def get_distribution_score
          return 1.0 if @partitions.empty?

          total_knowledge = @global_knowledge.size
          return 1.0 if total_knowledge.zero?

          distributed_count = @partitions.values.sum { |p| p.entries.size }

          average_per_agent = distributed_count.to_f / @partitions.size
          ideal_distribution = total_knowledge.to_f / @partitions.size

          [1.0, average_per_agent / ideal_distribution].min
        end

        # Get knowledge summary for an agent
        # @param agent_id [String] Agent identifier
        # @return [KnowledgeSummary] Knowledge summary
        def get_knowledge_summary(agent_id)
          partition = @partitions[agent_id]

          unless partition
            return KnowledgeSummary.new(
              agent_id: agent_id,
              entry_count: 0,
              categories: {},
              last_updated: DateTime.now,
              provenance_depth: 0
            )
          end

          categories = Hash.new(0)
          partition.entries.values.each do |entry|
            entry.tags.each { |tag| categories[tag] += 1 }
          end

          KnowledgeSummary.new(
            agent_id: agent_id,
            entry_count: partition.entries.size,
            categories: categories,
            last_updated: partition.updated_at,
            provenance_depth: partition.provenance.length
          )
        end

        # Prune expired knowledge entries
        # @return [Integer] Number of entries pruned
        def prune_expired_knowledge
          pruned_count = 0
          now = DateTime.now

          @partitions.each do |agent_id, partition|
            expired_keys = partition.entries.select do |_, entry|
              entry.expires_at && entry.expires_at < now
            end.keys

            expired_keys.each do |key|
              partition.entries.delete(key)
              pruned_count += 1
            end
          end

          pruned_count
        end

        # Transfer knowledge between agents
        # @param source_agent_id [String] Source agent
        # @param target_agent_id [String] Target agent
        # @param keys [Array<String>, nil] Keys to transfer (all if not specified)
        # @return [Integer] Number of entries transferred
        def transfer_knowledge(source_agent_id, target_agent_id, keys = nil)
          source_partition = @partitions[source_agent_id]
          target_partition = @partitions[target_agent_id]

          return 0 unless source_partition && target_partition

          keys_to_transfer = keys || source_partition.entries.keys
          transferred_count = 0

          keys_to_transfer.each do |key|
            if can_access(target_agent_id, key)
              entry = source_partition.entries[key]
              if entry
                distribute_knowledge(target_agent_id, key, entry.value, source_agent_id)
                transferred_count += 1
              end
            end
          end

          transferred_count
        end

        private

        LEVEL_HIERARCHY = [
          Types::KnowledgeLevel::MINIMAL,
          Types::KnowledgeLevel::LIMITED,
          Types::KnowledgeLevel::PARTIAL,
          Types::KnowledgeLevel::FULL
        ].freeze

        def determine_access_level(role)
          case role
          when Types::AgentRole::COORDINATOR then Types::KnowledgeLevel::FULL
          when Types::AgentRole::EXECUTOR then Types::KnowledgeLevel::PARTIAL
          when Types::AgentRole::VALIDATOR then Types::KnowledgeLevel::PARTIAL
          when Types::AgentRole::SPECIALIST then Types::KnowledgeLevel::LIMITED
          when Types::AgentRole::OBSERVER then Types::KnowledgeLevel::MINIMAL
          else Types::KnowledgeLevel::MINIMAL
          end
        end

        def check_strict_access(agent_id, key)
          policies = @access_policies[agent_id] || []

          policies.any? do |policy|
            matches_pattern(key, policy.allowed_keys) &&
              !matches_pattern(key, policy.denied_keys) &&
              evaluate_conditions(policy.conditions)
          end
        end

        def check_moderate_access(agent_id, key)
          partition = @partitions[agent_id]
          return false unless partition

          global_entry = @global_knowledge[key]
          return true unless global_entry

          agent_level_index = LEVEL_HIERARCHY.index(partition.access_level)
          knowledge_level_index = LEVEL_HIERARCHY.index(global_entry.level)

          agent_level_index >= knowledge_level_index
        end

        def matches_pattern(key, patterns)
          patterns.any? do |pattern|
            pattern == '*' ||
              (pattern.end_with?('*') && key.start_with?(pattern.chomp('*'))) ||
              key == pattern
          end
        end

        def evaluate_conditions(conditions)
          conditions.all? do |condition|
            case condition.type
            when Types::ConditionType::TIME
              true
            when Types::ConditionType::TASK
              true
            when Types::ConditionType::CONTEXT
              true
            when Types::ConditionType::PERFORMANCE
              true
            else
              true
            end
          end
        end

        def can_share(entry, target_agent_id)
          target_partition = @partitions[target_agent_id]
          return false unless target_partition

          target_level_index = LEVEL_HIERARCHY.index(target_partition.access_level)
          entry_level_index = LEVEL_HIERARCHY.index(entry.level)

          target_level_index >= entry_level_index
        end

        def generate_id
          "#{Time.now.to_i}-#{SecureRandom.alphanumeric(9)}"
        end

        def generate_origin_id
          "origin-#{generate_id}"
        end
      end
    end
  end
end
