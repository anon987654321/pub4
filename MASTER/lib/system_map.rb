# frozen_string_literal: true

module MASTER
  module SystemMap
    def self.quick_context
      root_path = File.expand_path('../../..', __dir__)
      module_count = Dir[File.join(root_path, 'lib', '**', '*.rb')].count
      bin_count = Dir[File.join(root_path, 'bin', '*')].reject { |f| File.directory?(f) }.count
      version = defined?(MASTER::VERSION) ? MASTER::VERSION : '52.0'
      "MASTER v#{version}: #{module_count} Ruby modules, #{bin_count} CLI tools, autoloaded on #{RUBY_PLATFORM}"
    end
    
    def self.architecture
      {
        entry: 'bin/cli → lib/master.rb',
        execution: 'lib/core/executor.rb parses code blocks',
        routing: 'lib/llm.rb (9-tier model routing)',
        capabilities: %w[self_modification agentic_execution multi_model replicate openbsd_security]
      }
    end
  end
end
