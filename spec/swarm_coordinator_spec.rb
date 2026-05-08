# frozen_string_literal: true

begin
  require 'superinstance/equipment/swarm_coordinator'
rescue LoadError
  $LOAD_PATH.unshift File.expand_path('../lib', __dir__)
  require 'equipment/swarm_coordinator'
end

require 'rspec/core'
require 'rspec/expectations'
require 'rspec/mocks'

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end
  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end
  config.disable_monkey_patching!
end

RSpec.describe SuperInstance::Equipment::SwarmCoordinator::SwarmCoordinator do
  let(:coordinator) { described_class.new }

  describe '#initialize' do
    it 'creates with default parameters' do
      expect(coordinator).to be_a(described_class)
      expect(coordinator.config).to be_a(SwarmCoordinator::SwarmConfig)
    end

    it 'accepts custom configuration' do
      custom = described_class.new({
        max_agents: 20,
        enable_hierarchy: false
      })

      expect(custom.config.max_agents).to eq(20)
      expect(custom.config.enable_hierarchy).to be false
    end
  end

  describe '#register_agent' do
    it 'registers an agent and returns true' do
      agent = {
        id: 'agent-1',
        name: 'Test Agent',
        role: :executor,
        capabilities: [:coding, :testing],
        status: :idle
      }
      result = coordinator.register_agent(agent)
      expect(result).to be true
    end

    it 'prevents duplicate registration' do
      agent = {
        id: 'agent-dup',
        name: 'Dup Agent',
        role: :executor,
        capabilities: [:coding]
      }
      coordinator.register_agent(agent)
      expect {
        coordinator.register_agent(agent)
      }.to raise_error(SwarmCoordinator::Error, /already registered/)
    end
  end

  describe '#unregister_agent' do
    it 'unregisters an existing agent' do
      agent = {
        id: 'agent-remove',
        name: 'Remove Agent',
        role: :executor,
        capabilities: [:test]
      }
      coordinator.register_agent(agent)
      result = coordinator.unregister_agent(agent[:id])
      expect(result).to be true
    end

    it 'returns false for non-existent agent' do
      result = coordinator.unregister_agent('non-existent-id')
      expect(result).to be false
    end
  end

  describe '#get_state' do
    it 'returns current swarm state' do
      state = coordinator.get_state
      expect(state).to be_a(SwarmCoordinator::SwarmState)
      expect(state.swarm_id).to be_a(String)
    end

    it 'handles no agents gracefully' do
      state = coordinator.get_state
      expect(state.status).to eq(SwarmCoordinator::Types::ExecutionStatus::IDLE)
    end
  end

  describe '#get_performance_metrics' do
    it 'returns empty metrics when no agents' do
      metrics = coordinator.get_performance_metrics
      expect(metrics).to be_a(Hash)
    end

    it 'returns specific agent metrics when agent_id provided' do
      agent = { id: 'perf-agent', name: 'Perf', role: :executor, capabilities: [:test] }
      coordinator.register_agent(agent)
      metrics = coordinator.get_performance_metrics('perf-agent')
      expect(metrics).to be_a(Array)
    end
  end

  describe 'edge cases' do
    it 'handles no agents gracefully' do
      state = coordinator.get_state
      expect(state.active_agent_count).to eq(0)
    end

    it 'handles weight normalization through config' do
      coordinator = described_class.new
      coordinator.register_agent({
        id: 'w1',
        name: 'Weight 1',
        role: :executor,
        capabilities: [:coding]
      })
      coordinator.register_agent({
        id: 'w2',
        name: 'Weight 2',
        role: :executor,
        capabilities: [:coding]
      })

      state = coordinator.get_state
      expect(state.metrics.total_agents).to eq(2)
    end
  end
end

RSpec.describe SuperInstance::Equipment::SwarmCoordinator::AgentOrchestrator do
  let(:orchestrator) { described_class.new(max_agents: 10) }

  describe '#initialize' do
    it 'creates with configuration' do
      expect(orchestrator).to be_a(described_class)
    end
  end

  describe '#register_agent' do
    it 'registers agent and returns true' do
      profile = AgentOrchestrator::AgentProfile.new(
        id: 'agent-test',
        name: 'Test',
        role: :executor,
        capabilities: [:test],
        status: SwarmCoordinator::Types::ExecutionStatus::IDLE,
        hierarchy_level: 0,
        parent_agent_id: nil,
        child_agent_ids: [],
        metadata: {},
        current_load: 0,
        weight: 1.0
      )

      result = orchestrator.register_agent(profile)
      expect(result).to be true
    end
  end

  describe '#unregister_agent' do
    it 'unregisters existing agent' do
      profile = AgentOrchestrator::AgentProfile.new(
        id: 'agent-remove',
        name: 'Remove Test',
        role: :executor,
        capabilities: [:test],
        status: SwarmCoordinator::Types::ExecutionStatus::IDLE,
        hierarchy_level: 0,
        parent_agent_id: nil,
        child_agent_ids: [],
        metadata: {},
        current_load: 0,
        weight: 1.0
      )

      orchestrator.register_agent(profile)
      result = orchestrator.unregister_agent('agent-remove')
      expect(result).to be true
    end

    it 'returns false for unknown agent' do
      result = orchestrator.unregister_agent('nonexistent')
      expect(result).to be false
    end
  end

  describe 'weight adjustment' do
    it 'adjusts agent weight for performance' do
      profile = AgentOrchestrator::AgentProfile.new(
        id: 'weight-test',
        name: 'Weight Test',
        role: :executor,
        capabilities: [:test],
        status: SwarmCoordinator::Types::ExecutionStatus::IDLE,
        hierarchy_level: 0,
        parent_agent_id: nil,
        child_agent_ids: [],
        metadata: {},
        current_load: 0,
        weight: 1.0
      )

      orchestrator.register_agent(profile)
      expect {
        orchestrator.adjust_agent_weight('weight-test', 0.8)
      }.not_to raise_error
    end
  end
end

RSpec.describe SuperInstance::Equipment::SwarmCoordinator::ResultAggregator do
  let(:aggregator) { described_class.new }

  describe '#initialize' do
    it 'creates with default config' do
      expect(aggregator).to be_a(described_class)
    end
  end

  describe '#aggregate' do
    it 'aggregates results into a hash' do
      results = {
        task1: { result: 'success', confidence: 0.9 },
        task2: { result: 'partial', confidence: 0.5 }
      }

      aggregated = aggregator.aggregate(results)
      expect(aggregated).to be_a(Hash)
      expect(aggregated).to have_key(:results)
    end
  end
end

RSpec.describe SuperInstance::Equipment::SwarmCoordinator::TaskDecomposer do
  let(:decomposer) { described_class.new(max_parallelism: 5) }

  describe '#initialize' do
    it 'creates with configuration' do
      expect(decomposer).to be_a(described_class)
    end
  end

  describe '#decompose' do
    it 'decomposes a task into dependency graph' do
      result = decomposer.decompose('Test task', {})

      expect(result).to be_a(Hash)
      expect(result).to have_key(:nodes)
      expect(result).to have_key(:dependencies)
    end
  end
end

RSpec.describe SuperInstance::Equipment::SwarmCoordinator::AsymmetricKnowledge do
  let(:knowledge) { described_class.new }

  describe '#initialize' do
    it 'creates with default isolation' do
      expect(knowledge).to be_a(described_class)
    end
  end

  describe '#create_partition' do
    it 'creates knowledge partition for agent' do
      expect {
        knowledge.create_partition('agent-1', :executor)
      }.not_to raise_error
    end
  end

  describe '#get_partition' do
    it 'returns partition for known agent' do
      knowledge.create_partition('agent-2', :executor)
      partition = knowledge.get_partition('agent-2')
      expect(partition).to be_a(Hash)
    end
  end

  describe 'weight and knowledge distribution' do
    it 'provides distribution score' do
      knowledge.create_partition('agent-1', :executor)
      knowledge.create_partition('agent-2', :executor)

      score = knowledge.get_distribution_score
      expect(score).to be_a(Numeric)
    end
  end
end

RSpec.describe SuperInstance::Equipment::SwarmCoordinator::Types do
  describe 'AgentRole' do
    it 'has expected values' do
      expect(Types::AgentRole::COORDINATOR).to eq(:coordinator)
      expect(Types::AgentRole::EXECUTOR).to eq(:executor)
      expect(Types::AgentRole::OBSERVER).to eq(:observer)
      expect(Types::AgentRole::VALIDATOR).to eq(:validator)
      expect(Types::AgentRole::SPECIALIST).to eq(:specialist)
    end
  end

  describe 'ExecutionStatus' do
    it 'has expected values' do
      expect(Types::ExecutionStatus::IDLE).to eq(:idle)
      expect(Types::ExecutionStatus::RUNNING).to eq(:running)
      expect(Types::ExecutionStatus::COMPLETED).to eq(:completed)
      expect(Types::ExecutionStatus::FAILED).to eq(:failed)
    end
  end

  describe 'ConflictResolutionStrategy' do
    it 'has expected values' do
      expect(Types::ConflictResolutionStrategy::VOTING).to eq(:voting)
      expect(Types::ConflictResolutionStrategy::WEIGHTED).to eq(:weighted)
      expect(Types::ConflictResolutionStrategy::HIERARCHICAL).to eq(:hierarchical)
      expect(Types::ConflictResolutionStrategy::CONSENSUS).to eq(:consensus)
    end
  end
end
