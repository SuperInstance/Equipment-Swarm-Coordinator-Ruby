# frozen_string_literal: true

require 'rake'
require 'rake/tasklib'

namespace :syntax do
  desc 'Check Ruby syntax for all lib files'
  task :check do
    Dir.glob('lib/**/*.rb').each do |file|
      result = `ruby -c #{file}`
      if $?.success?
        puts "✓ #{file}"
      else
        puts "✗ #{file}"
        puts result
        exit 1
      end
    end
    puts 'All files passed syntax check.'
  end
end

task default: 'syntax:check'
