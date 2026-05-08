# frozen_string_literal: true

require_relative 'lib/equipment/swarm_coordinator/version'

Gem::Specification.new do |spec|
  spec.name = 'superinstance-equipment-swarm-coordinator'
  spec.version = SuperInstance::Equipment::SwarmCoordinator::VERSION
  spec.summary = 'Swarm coordination equipment for SuperInstance agents'
  spec.authors = ['SuperInstance Ecosystem']
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.0'

  spec.homepage = 'https://github.com/SuperInstance/Equipment-Swarm-Coordinator'
  spec.description = <<~DESC
    Equipment for orchestrating multiple agents in origin-centric networks
    with asymmetrical knowledge distribution.
  DESC

  spec.metadata = {
    'bug_tracker_uri' => 'https://github.com/SuperInstance/Equipment-Swarm-Coordinator/issues',
    'changelog_uri' => 'https://github.com/SuperInstance/Equipment-Swarm-Coordinator/releases'
  }

  spec.files = Dir.glob('{lib/**/*,LICENSE.txt,README.md}')
  spec.require_path = 'lib'

  spec.add_development_dependency 'rspec', '~> 3.12'

  spec.add_dependency 'concurrent-ruby', '~> 1.2'
end
