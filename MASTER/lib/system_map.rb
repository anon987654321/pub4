# frozen_string_literal: true

module SystemMap
  def self.quick_context
    module_count = Dir[File.join(MASTER::ROOT, 'MASTER', 'lib', '**', '*.rb')].count
    bin_count = Dir[File.join(MASTER::ROOT, 'MASTER', 'bin', '*')].reject { |f| File.directory?(f) }.count
    "MASTER v#{MASTER::VERSION}: #{module_count} Ruby modules, #{bin_count} CLI tools, autoloaded on OpenBSD"
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
