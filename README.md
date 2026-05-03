# @superinstance/equipment-swarm-coordinator

> Equipment for orchestrating multiple agents in origin-centric networks with asymmetrical knowledge distribution.

## Brand Line

> Multi-agent orchestration with provenance tracking — the Cocapn fleet's swarm brain.

## Installation

```bash
gem install superinstance-equipment-swarm-coordinator
```

Or with Bundler:

```ruby
# Gemfile
gem 'superinstance-equipment-swarm-coordinator'
```

```bash
bundle install
```

## Quick Start

```ruby
require 'equipment/swarm_coordinator'

# Create a swarm coordinator
coordinator = SwarmCoordinator.new(
  max_agents: 10,
  enable_hierarchy: true,
  knowledge_isolation: :moderate,
  adaptive_allocation: true
)

# Register agents
coordinator.register_agent(
  id: 'agent-1',
  name: 'DataProcessor',
  role: :executor,
  capabilities: ['data_processing', 'computation'],
  status: :idle,
  hierarchy_level: 0,
  metadata: {}
)

# Execute a task
result = coordinator.execute_task('Process the data and generate report')
puts result[:value]
```

## Core Components

### SwarmCoordinator

The main equipment class that orchestrates the entire swarm:

```ruby
coordinator = SwarmCoordinator.new(
  max_agents: 10,                # Maximum number of agents
  enable_hierarchy: true,        # Enable hierarchical structures
  max_hierarchy_depth: 3,        # Maximum hierarchy depth
  knowledge_isolation: :moderate, # Knowledge isolation level
  task_timeout: 30_000,          # Task timeout in ms
  adaptive_allocation: true,    # Enable adaptive allocation
  conflict_resolution: :weighted, # Conflict resolution strategy
  performance_window_size: 100   # Performance tracking window
)

# Register agents
coordinator.register_agent(
  id: 'coordinator-agent',
  name: 'MainCoordinator',
  role: :coordinator,
  capabilities: ['coordination', 'planning'],
  status: :idle,
  hierarchy_level: 0,
  metadata: {}
)

# Execute tasks
result = coordinator.execute_task('Complex task description')

# Get swarm state
state = coordinator.get_state
puts state[:metrics]
```

### AgentOrchestrator

Manages agent registration, hierarchy, and task distribution:

```ruby
orchestrator = AgentOrchestrator.new(
  max_agents: 100,
  enable_hierarchy: true,
  max_hierarchy_depth: 5,
  default_timeout: 30_000,
  load_balancing: true
)

# Register agents
orchestrator.register_agent(
  id: 'executor-1',
  name: 'TaskExecutor',
  role: :executor,
  capabilities: ['computation', 'data_processing'],
  status: :idle,
  hierarchy_level: 1,
  metadata: {}
)

# Select best agent for a task
agent = orchestrator.select_best_agent(
  ['computation'],
  :executor
)

# Get orchestrator statistics
stats = orchestrator.get_statistics
```

### AsymmetricKnowledge

Manages asymmetrical knowledge distribution:

```ruby
knowledge_manager = AsymmetricKnowledge.new(
  isolation_level: :moderate,
  enable_caching: true,
  max_partition_size: 10_000,
  retention_period: 86_400_000, # 24 hours
  enable_provenance: true
)

# Create knowledge partition for agent
knowledge_manager.create_partition('agent-1', :executor)

# Distribute knowledge
knowledge_manager.distribute_knowledge(
  'agent-1',
  'database_connection_string',
  'postgresql://localhost:5432/db',
  'system'
)

# Set access policies
knowledge_manager.set_access_policy(
  source_agent_id: 'agent-1',
  target_agent_id: 'agent-2',
  allowed_keys: ['public_*'],
  denied_keys: ['private_*'],
  granted_level: :partial,
  conditions: []
)

# Get knowledge summary
summary = knowledge_manager.get_knowledge_summary('agent-1')
```

### TaskDecomposer

Breaks down complex tasks into parallel subtasks:

```ruby
decomposer = TaskDecomposer.new(
  max_parallelism: 10,
  min_task_size: 0.1,
  max_depth: 5,
  auto_dependency_detection: true,
  default_timeout: 60_000
)

# Decompose a task
graph = decomposer.decompose('Process large dataset and generate analytics')

# Get ready tasks
ready_tasks = decomposer.get_ready_tasks(graph, Set.new)

# Get statistics
stats = decomposer.get_statistics(graph)
puts "Total tasks: #{stats[:total_tasks]}"
puts "Critical path: #{stats[:critical_path].length}"
```

### ResultAggregator

Aggregates results from multiple agents with conflict resolution:

```ruby
aggregator = ResultAggregator.new(
  conflict_resolution: :weighted,
  enable_validation: true,
  min_confidence: 0.5,
  enable_caching: true,
  max_cache_size: 1_000,
  timeout: 30_000
)

# Aggregate results
results = [
  {
    agent_id: 'agent-1',
    value: { score: 0.95 },
    confidence: 0.9,
    execution_time: 150,
    timestamp: DateTime.now,
    metadata: {}
  },
  {
    agent_id: 'agent-2',
    value: { score: 0.88 },
    confidence: 0.85,
    execution_time: 120,
    timestamp: DateTime.now,
    metadata: {}
  }
]

aggregated = aggregator.aggregate_task_results('task_1', results)
puts "Final value: #{aggregated[:value]}"
puts "Confidence: #{aggregated[:confidence]}"
puts "Conflicts: #{aggregated[:conflicts].length}"
```

## Agent Roles

The coordinator supports several agent roles:

| Role | Description | Knowledge Level |
|------|-------------|-----------------|
| `coordinator` | Coordinates other agents | Full |
| `executor` | Executes tasks | Partial |
| `validator` | Validates results | Partial |
| `specialist` | Specialized for specific tasks | Limited |
| `observer` | Observes and reports | Minimal |

## Conflict Resolution Strategies

| Strategy | Description |
|----------|-------------|
| `voting` | Democratic voting among agents |
| `weighted` | Weighted by confidence and performance |
| `hierarchical` | Based on agent hierarchy level |
| `consensus` | Seek consensus between agents |

## Knowledge Isolation Levels

| Level | Description |
|-------|-------------|
| `strict` | Agents can only access explicitly granted knowledge |
| `moderate` | Agents can access knowledge at or below their level |
| `relaxed` | Agents can access all knowledge |

## Task Decomposition Strategies

| Strategy | Description |
|----------|-------------|
| `parallel` | Split into independent parallel tasks |
| `sequential` | Split into sequential stages |
| `pipeline` | Split into pipeline stages |
| `map_reduce` | Map-reduce pattern |
| `divide_conquer` | Divide and conquer approach |

## Fleet Context

Part of the Cocapn fleet. Related repos:

- [Equipment-Consensus-Engine](https://github.com/SuperInstance/Equipment-Consensus-Engine) — multi-agent deliberation
- [plato-sdk](https://github.com/SuperInstance/plato-sdk) — agent communication protocol
- [JetsonClaw1-vessel](https://github.com/Lucineer/JetsonClaw1-vessel) — edge-native agent case study
- [AIR](https://github.com/SuperInstance/AIR) — adaptive intelligence runtime

---

🦐 Cocapn fleet — lighthouse keeper architecture
