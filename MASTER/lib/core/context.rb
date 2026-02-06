# frozen_string_literal: true

module MASTER
  module Context
    # System awareness and purpose context for LLM prompts

    class << self
      def system_prompt
        <<~PROMPT
          You are MASTER #{VERSION}, an AI system administrator and developer assistant.

          ## Your Own Structure
          #{self_structure}

          ## Your Environment
          #{environment_info}

          ## Your Purpose
          You help build and maintain billion-user scale web applications.
          You administer OpenBSD servers with security-first principles.
          You write Ruby, Rails, and shell code that executes immediately.

          ## Your Capabilities
          - You CAN execute shell commands. Output code blocks and they run.
          - You CAN modify files. Use heredocs or echo/cat commands.
          - You CAN query system state. Run commands to check status.
          - You have FULL access to the filesystem and network.
          - You CAN modify your own code in lib/ to improve yourself.

          ## Execution Rules
          - Shell code in ```sh blocks executes automatically
          - Ruby code in ```ruby blocks executes automatically
          - Results feed back to you for next steps
          - Safety module blocks dangerous patterns

          ## Style
          - dmesg-style trace output for all operations
          - Terse, Unix-like responses
          - No markdown in explanations, only in code blocks
          - Full transparency on all processes
          - Show your reasoning as trace lines

          ## Current Session
          #{session_info}
        PROMPT
      end

      def self_structure
        root = MASTER::ROOT
        structure = []
        structure << "Entry: bin/cli (starts MASTER)"
        structure << "Main: lib/master.rb (module loader)"
        
        # Core components
        core_files = Dir[File.join(root, 'lib', '*.rb')].map { |f| File.basename(f, '.rb') }
        structure << "Components: #{core_files.join(', ')}"
        
        # Submodules
        %w[core framework plugins agents cli views principles personas config].each do |dir|
          path = File.join(root, 'lib', dir)
          if File.directory?(path)
            files = Dir[File.join(path, '*.{rb,yml}')].map { |f| File.basename(f, '.*') }
            structure << "lib/#{dir}/: #{files.join(', ')}" if files.any?
          end
        end
        
        # Apps (bp/)
        bp_path = File.join(root, 'bp')
        if File.directory?(bp_path)
          apps = Dir[File.join(bp_path, '*')].select { |f| File.directory?(f) }.map { |f| File.basename(f) }
          structure << "Apps (bp/): #{apps.join(', ')}" if apps.any?
        end
        
        # Deploy configs
        deploy_path = File.join(root, 'deploy')
        if File.directory?(deploy_path)
          configs = Dir[File.join(deploy_path, '*.{rb,yml,sh}')].map { |f| File.basename(f) }
          structure << "Deploy: #{configs.join(', ')}" if configs.any?
        end
        
        structure.join("\n")
      end

      def environment_info
        info = []
        info << "Platform: #{platform_name}"
        info << "Ruby: #{RUBY_VERSION}"
        info << "Hostname: #{`hostname`.strip rescue 'unknown'}"
        info << "User: #{ENV['USER'] || ENV['USERNAME'] || 'unknown'}"
        info << "PWD: #{Dir.pwd}"
        info << "Root: #{MASTER::ROOT}"

        if openbsd?
          info << "Kernel: #{`uname -r`.strip rescue 'unknown'}"
          info << "Memory: #{`sysctl -n hw.physmem`.to_i / 1024 / 1024}MB" rescue nil
        end

        info.compact.join("\n")
      end

      def session_info
        session_file = File.join(Paths.data, 'session.json')
        return "New session" unless File.exist?(session_file)

        begin
          data = JSON.parse(File.read(session_file), symbolize_names: true)
          "Resumed: #{data[:name]} | Commands: #{data[:command_count]} | Cost: $#{'%.2f' % data[:total_cost]}"
        rescue StandardError
          "New session"
        end
      end

      def platform_name
        case RUBY_PLATFORM
        when /openbsd/ then "OpenBSD"
        when /darwin/ then "macOS"
        when /linux/ then "Linux"
        when /cygwin/ then "Cygwin"
        when /mingw|mswin/ then "Windows"
        else RUBY_PLATFORM
        end
      end

      def openbsd?
        RUBY_PLATFORM.include?('openbsd')
      end
    end
  end
end
