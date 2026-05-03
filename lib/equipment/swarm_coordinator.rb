# frozen_string_literal: true

module SuperInstance
  module Equipment
    module SwarmCoordinator
      VERSION = '1.0.0'.freeze

      class Error < StandardError; end

      autoload :SwarmCoordinator, 'equipment/swarm_coordinator/swarm_coordinator'
      autoload :AgentOrchestrator, 'equipment/swarm_coordinator/agent_orchestrator'
      autoload :TaskDecomposer, 'equipment/swarm_coordinator/task_decomposer'
      autoload :ResultAggregator, 'equipment/swarm_coordinator/result_aggregator'
      autoload :AsymmetricKnowledge, 'equipment/swarm_coordinator/asymmetric_knowledge'
      autoload :Types, 'equipment/swarm_coordinator/types'
    end
  end
end
