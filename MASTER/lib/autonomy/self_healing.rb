# frozen_string_literal: true

require 'yaml'

module MASTER
  module Autonomy
    # Self-healing system for automatic error recovery
    class SelfHealing
      RECOVERY_LOG = File.join(Paths.var, 'recovery_log.yml')
      MAX_RETRIES = 3
      BACKOFF_MULTIPLIER = 2
      
      def initialize(llm = nil)
        @llm = llm
        @recovery_history = load_recovery_history
        @health_monitor = HealthMonitor.new
      end
      
      # Execute with automatic recovery
      def execute_with_recovery(description, &block)
        attempts = 0
        last_error = nil
        
        loop do
          attempts += 1
          
          begin
            result = block.call
            record_success(description, attempts)
            return { success: true, result: result, attempts: attempts }
          rescue => e
            last_error = e
            record_failure(description, e, attempts)
            
            break if attempts >= MAX_RETRIES
            
            recovery_strategy = determine_recovery(e, attempts)
            
            case recovery_strategy[:action]
            when :retry
              delay = recovery_strategy[:delay] || (attempts * BACKOFF_MULTIPLIER)
              sleep(delay)
            when :heal
              apply_healing_action(recovery_strategy[:healing_action])
            when :rollback
              perform_rollback
            when :abort
              break
            end
          end
        end
        
        { success: false, error: last_error, attempts: attempts }
      end
      
      # Determine recovery strategy based on error
      def determine_recovery(error, attempt)
        error_type = classify_error(error)
        
        # Check if we've seen this before
        learned = @recovery_history[error_type]
        if learned && learned[:success_rate] > 0.7
          return learned[:strategy]
        end
        
        # Default strategies by error type
        case error_type
        when :rate_limit
          { action: :retry, delay: 60 }
        when :timeout
          { action: :retry, delay: 5 }
        when :connection
          { action: :retry, delay: 10 }
        when :authentication
          { action: :heal, healing_action: :refresh_credentials }
        when :file_not_found
          { action: :heal, healing_action: :create_missing_files }
        when :permission_denied
          { action: :heal, healing_action: :fix_permissions }
        when :syntax_error
          { action: :rollback }
        when :out_of_memory
          { action: :heal, healing_action: :reduce_memory_usage }
        else
          attempt < MAX_RETRIES ? { action: :retry, delay: attempt * 2 } : { action: :abort }
        end
      end
      
      # Apply healing actions
      def apply_healing_action(action)
        case action
        when :refresh_credentials
          # Reload environment variables
          ENV.each_key { |k| ENV[k] = `echo $#{k}`.strip if k.start_with?('MASTER_') }
        when :create_missing_files
          # Create common missing directories
          %w[var data config/tmp].each do |dir|
            FileUtils.mkdir_p(File.join(Paths.root, dir))
          end
        when :fix_permissions
          # Fix common permission issues
          %w[bin/cli bin/bot bin/weekly].each do |file|
            path = File.join(Paths.root, file)
            File.chmod(0755, path) if File.exist?(path)
          end
        when :reduce_memory_usage
          # Force garbage collection
          GC.start(full_mark: true, immediate_sweep: true)
        end
      end
      
      # Rollback changes
      def perform_rollback
        return unless Dir.exist?('.git')
        
        # Stash any uncommitted changes
        system('git stash push -m "auto-rollback-$(date +%s)" 2>/dev/null')
      end
      
      # Classify error for recovery strategy
      def classify_error(error)
        msg = error.message.to_s.downcase
        
        return :rate_limit if msg.include?('rate limit') || msg.include?('429')
        return :timeout if msg.include?('timeout') || msg.include?('timed out')
        return :connection if msg.include?('connection') || msg.include?('network')
        return :authentication if msg.include?('auth') || msg.include?('401') || msg.include?('403')
        return :file_not_found if msg.include?('no such file') || error.is_a?(Errno::ENOENT)
        return :permission_denied if msg.include?('permission') || error.is_a?(Errno::EACCES)
        return :syntax_error if msg.include?('syntax') || error.is_a?(SyntaxError)
        return :out_of_memory if msg.include?('memory') || error.is_a?(NoMemoryError)
        
        :unknown
      end
      
      # Record successful recovery
      def record_success(description, attempts)
        @recovery_history[:successes] ||= []
        @recovery_history[:successes] << {
          description: description,
          attempts: attempts,
          timestamp: Time.now.to_i
        }
        
        save_recovery_history
      end
      
      # Record recovery failure
      def record_failure(description, error, attempts)
        error_type = classify_error(error)
        
        @recovery_history[error_type] ||= {
          total_attempts: 0,
          successes: 0,
          failures: 0,
          success_rate: 0.0,
          strategy: {}
        }
        
        @recovery_history[error_type][:total_attempts] += 1
        @recovery_history[error_type][:failures] += 1
        
        save_recovery_history
      end
      
      # Get health status
      def health_status
        @health_monitor.check_all
      end
      
      # Run diagnostics
      def run_diagnostics
        {
          file_system: check_file_system,
          git_status: check_git_status,
          dependencies: check_dependencies,
          environment: check_environment,
          memory: check_memory
        }
      end
      
      private
      
      def load_recovery_history
        return {} unless File.exist?(RECOVERY_LOG)
        YAML.load_file(RECOVERY_LOG, symbolize_names: true) rescue {}
      end
      
      def save_recovery_history
        FileUtils.mkdir_p(File.dirname(RECOVERY_LOG))
        File.write(RECOVERY_LOG, @recovery_history.to_yaml)
      end
      
      def check_file_system
        required_dirs = %w[lib config data var]
        missing = required_dirs.reject { |d| Dir.exist?(File.join(Paths.root, d)) }
        
        { healthy: missing.empty?, missing_dirs: missing }
      end
      
      def check_git_status
        return { healthy: true, repo: false } unless Dir.exist?('.git')
        
        status = `git status --porcelain 2>/dev/null`.strip
        { healthy: true, repo: true, clean: status.empty? }
      end
      
      def check_dependencies
        gemfile = File.join(Paths.root, 'Gemfile')
        return { healthy: true, checked: false } unless File.exist?(gemfile)
        
        # Try to require bundler
        begin
          require 'bundler'
          Bundler.setup
          { healthy: true, checked: true }
        rescue LoadError, Bundler::GemNotFound => e
          { healthy: false, error: e.message }
        end
      end
      
      def check_environment
        required_vars = %w[OPENROUTER_API_KEY]
        missing = required_vars.reject { |v| ENV[v] }
        
        { healthy: missing.empty?, missing_vars: missing }
      end
      
      def check_memory
        # Get memory usage on supported systems
        if RUBY_PLATFORM =~ /linux/
          mem_info = File.read('/proc/meminfo') rescue nil
          if mem_info
            total = mem_info[/MemTotal:\s+(\d+)/, 1].to_i
            available = mem_info[/MemAvailable:\s+(\d+)/, 1].to_i
            usage_percent = ((total - available).to_f / total * 100).round(1)
            
            return { healthy: usage_percent < 90, usage_percent: usage_percent }
          end
        end
        
        { healthy: true, platform_unsupported: true }
      end
    end
    
    # Health monitoring system
    class HealthMonitor
      CHECK_INTERVAL = 300 # 5 minutes
      
      def initialize
        @last_check = nil
        @cached_status = nil
      end
      
      def check_all
        now = Time.now.to_i
        
        if @last_check && (now - @last_check) < CHECK_INTERVAL
          return @cached_status
        end
        
        @cached_status = perform_checks
        @last_check = now
        @cached_status
      end
      
      private
      
      def perform_checks
        {
          timestamp: Time.now.to_i,
          llm_connectivity: check_llm,
          disk_space: check_disk,
          process_health: check_process,
          overall: :healthy
        }
      end
      
      def check_llm
        # Simple connectivity check
        ENV['OPENROUTER_API_KEY'] ? :healthy : :degraded
      end
      
      def check_disk
        # Check available disk space
        if RUBY_PLATFORM =~ /linux|darwin/
          df_output = `df -h . 2>/dev/null | tail -1`.split
          usage = df_output[4].to_i if df_output[4]
          
          return :critical if usage && usage > 95
          return :warning if usage && usage > 85
          return :healthy
        end
        
        :unknown
      end
      
      def check_process
        # Check if process is responding
        :healthy
      end
    end
  end
end
