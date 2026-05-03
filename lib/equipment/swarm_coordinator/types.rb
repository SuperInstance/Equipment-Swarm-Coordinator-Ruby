# frozen_string_literal: true

# Shared type constants for the Equipment-Swarm-Coordinator
module SuperInstance
  module Equipment
    module SwarmCoordinator
      module Types
        extend self

        # Role of an agent in the swarm
        module AgentRole
          COORDINATOR = :coordinator.freeze
          EXECUTOR = :executor.freeze
          OBSERVER = :observer.freeze
          VALIDATOR = :validator.freeze
          SPECIALIST = :specialist.freeze

          VALUES = [COORDINATOR, EXECUTOR, OBSERVER, VALIDATOR, SPECIALIST].freeze
        end

        # Priority level for tasks
        module TaskPriority
          CRITICAL = :critical.freeze
          HIGH = :high.freeze
          NORMAL = :normal.freeze
          LOW = :low.freeze

          VALUES = [CRITICAL, HIGH, NORMAL, LOW].freeze
        end

        # Execution status
        module ExecutionStatus
          IDLE = :idle.freeze
          RUNNING = :running.freeze
          PAUSED = :paused.freeze
          COMPLETED = :completed.freeze
          FAILED = :failed.freeze

          VALUES = [IDLE, RUNNING, PAUSED, COMPLETED, FAILED].freeze
        end

        # Knowledge access level
        module KnowledgeLevel
          MINIMAL = :minimal.freeze
          LIMITED = :limited.freeze
          PARTIAL = :partial.freeze
          FULL = :full.freeze

          VALUES = [MINIMAL, LIMITED, PARTIAL, FULL].freeze
        end

        # Strategy for conflict resolution
        module ConflictResolutionStrategy
          VOTING = :voting.freeze
          WEIGHTED = :weighted.freeze
          HIERARCHICAL = :hierarchical.freeze
          CONSENSUS = :consensus.freeze

          VALUES = [VOTING, WEIGHTED, HIERARCHICAL, CONSENSUS].freeze
        end

        # Knowledge isolation level
        module IsolationLevel
          STRICT = :strict.freeze
          MODERATE = :moderate.freeze
          RELAXED = :relaxed.freeze

          VALUES = [STRICT, MODERATE, RELAXED].freeze
        end

        # Task type
        module TaskType
          COMPUTATION = :computation.freeze
          IO = :io.freeze
          COMMUNICATION = :communication.freeze
          DECISION = :decision.freeze
          VALIDATION = :validation.freeze
          AGGREGATION = :aggregation.freeze
          DECOMPOSITION = :decomposition.freeze
          SYNCHRONIZATION = :synchronization.freeze

          VALUES = [COMPUTATION, IO, COMMUNICATION, DECISION, VALIDATION, AGGREGATION, DECOMPOSITION, SYNCHRONIZATION].freeze
        end

        # Decomposition strategy
        module DecompositionStrategy
          PARALLEL = :parallel.freeze
          SEQUENTIAL = :sequential.freeze
          PIPELINE = :pipeline.freeze
          MAP_REDUCE = :map_reduce.freeze
          DIVIDE_CONQUER = :divide_conquer.freeze

          VALUES = [PARALLEL, SEQUENTIAL, PIPELINE, MAP_REDUCE, DIVIDE_CONQUER].freeze
        end

        # Conflict type
        module ConflictType
          VALUE = :value.freeze
          TYPE = :type.freeze
          CONFIDENCE = :confidence.freeze
          TIMEOUT = :timeout.freeze
          VALIDATION = :validation.freeze
        end

        # Aggregation method
        module AggregationMethod
          CONSENSUS = :consensus.freeze
          MAJORITY = :majority.freeze
          WEIGHTED = :weighted.freeze
          HIERARCHICAL = :hierarchical.freeze
          MERGED = :merged.freeze
          FIRST = :first.freeze
        end

        # Swarm event types
        module SwarmEventType
          AGENT_REGISTERED = :agent_registered.freeze
          AGENT_UNREGISTERED = :agent_unregistered.freeze
          TASK_ASSIGNED = :task_assigned.freeze
          TASK_COMPLETED = :task_completed.freeze
          TASK_FAILED = :task_failed.freeze
          CONFLICT_DETECTED = :conflict_detected.freeze
          CONFLICT_RESOLVED = :conflict_resolved.freeze
          KNOWLEDGE_DISTRIBUTED = :knowledge_distributed.freeze
          KNOWLEDGE_REQUESTED = :knowledge_requested.freeze
        end

        # Execution phase
        module ExecutionPhase
          DECOMPOSITION = :decomposition.freeze
          ALLOCATION = :allocation.freeze
          EXECUTION = :execution.freeze
          AGGREGATION = :aggregation.freeze
          COMPLETED = :completed.freeze
        end

        # Agent relationship type
        module RelationshipType
          PARENT = :parent.freeze
          CHILD = :child.freeze
          PEER = :peer.freeze
          SUPERVISOR = :supervisor.freeze
          SUBORDINATE = :subordinate.freeze
        end

        # Access condition type
        module ConditionType
          TIME = :time.freeze
          TASK = :task.freeze
          CONTEXT = :context.freeze
          PERFORMANCE = :performance.freeze
        end

        # Condition operator
        module ConditionOperator
          EQUALS = :equals.freeze
          NOT_EQUALS = :not_equals.freeze
          GREATER_THAN = :greater_than.freeze
          LESS_THAN = :less_than.freeze
          CONTAINS = :contains.freeze
        end
      end
    end
  end
end
