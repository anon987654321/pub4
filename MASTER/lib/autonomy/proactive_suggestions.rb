# frozen_string_literal: true

require 'yaml'
require 'json'

module MASTER
  module Autonomy
    # Proactive suggestion system that anticipates user needs
    class ProactiveSuggestions
      SUGGESTION_FILE = File.join(Paths.var, 'suggestions_learned.yml')
      
      def initialize
        @command_history = []
        @learned_patterns = load_learned_patterns
        @context_analyzer = ContextAnalyzer.new
      end
      
      # Analyze current state and suggest next action
      def suggest_next(current_command: nil, git_status: nil, file_state: nil)
        context = build_context(current_command, git_status, file_state)
        
        # Try pattern-based suggestions first
        pattern_suggestion = match_learned_pattern(context)
        return pattern_suggestion if pattern_suggestion
        
        # Fall back to rule-based suggestions
        rule_based_suggestion(context)
      end
      
      # Record command sequence for learning
      def record_command(command, success:, context: {})
        @command_history << {
          command: command,
          success: success,
          context: context,
          timestamp: Time.now.to_i
        }
        
        # Keep last 100 commands
        @command_history = @command_history.last(100)
        
        # Learn patterns from successful sequences
        learn_from_history if @command_history.size >= 3
      end
      
      # Get smart defaults for a command
      def smart_defaults(command)
        case command
        when 'scan'
          { depth: detect_project_size, exclude: common_ignores }
        when 'refactor'
          { safety: 'high', test: should_run_tests? }
        when 'evolve'
          { budget: estimate_safe_budget, iterations: estimate_iterations }
        when 'chamber'
          { models: recommend_models, timeout: estimate_timeout }
        else
          {}
        end
      end
      
      # Prevent common errors before they happen
      def check_preconditions(command, args)
        warnings = []
        
        case command
        when 'refactor'
          warnings << "Uncommitted changes detected" if uncommitted_changes?
          warnings << "No tests found - refactoring risky" unless tests_exist?
        when 'evolve'
          warnings << "Budget very low - may not converge" if args[:budget].to_f < 0.5
          warnings << "No git repo - can't revert failures" unless git_repo?
        when 'scan'
          warnings << "Large directory - scan may be slow" if directory_large?
        end
        
        warnings
      end
      
      private
      
      def build_context(current_command, git_status, file_state)
        {
          current_command: current_command,
          git_status: git_status,
          file_state: file_state,
          recent_commands: @command_history.last(5).map { |h| h[:command] },
          project_type: detect_project_type,
          time_of_day: Time.now.hour
        }
      end
      
      def match_learned_pattern(context)
        recent = context[:recent_commands]
        return nil if recent.nil? || recent.empty?
        
        @learned_patterns.each do |pattern|
          if pattern_matches?(pattern[:sequence], recent)
            return pattern[:next_command]
          end
        end
        
        nil
      end
      
      def pattern_matches?(pattern_seq, recent)
        return false if recent.size < pattern_seq.size
        recent.last(pattern_seq.size) == pattern_seq
      end
      
      def rule_based_suggestion(context)
        recent = context[:recent_commands] || []
        return nil if recent.empty?
        
        last_cmd = recent.last
        
        case last_cmd
        when 'scan'
          'refactor'
        when 'refactor'
          context[:git_status]&.include?('modified') ? 'commit' : 'test'
        when 'evolve'
          'test'
        when 'test'
          'commit'
        when /edit/
          edit_count = recent.count { |c| c&.start_with?('edit') }
          edit_count >= 3 ? 'lint' : nil
        else
          nil
        end
      end
      
      def learn_from_history
        # Find successful 2-3 command sequences
        successful_sequences = @command_history
          .select { |h| h[:success] }
          .last(20)
        
        return if successful_sequences.size < 3
        
        # Extract sequences of 2-3 commands
        (0...successful_sequences.size - 2).each do |i|
          seq = successful_sequences[i..i+1].map { |h| h[:command] }
          next_cmd = successful_sequences[i+2][:command]
          
          record_pattern(seq, next_cmd)
        end
        
        save_learned_patterns
      end
      
      def record_pattern(sequence, next_command)
        existing = @learned_patterns.find { |p| p[:sequence] == sequence }
        
        if existing
          existing[:count] += 1
          existing[:next_command] = next_command if existing[:count] > 2
        else
          @learned_patterns << {
            sequence: sequence,
            next_command: next_command,
            count: 1,
            learned_at: Time.now.to_i
          }
        end
        
        # Keep top 50 patterns
        @learned_patterns = @learned_patterns
          .sort_by { |p| -p[:count] }
          .first(50)
      end
      
      def load_learned_patterns
        return [] unless File.exist?(SUGGESTION_FILE)
        YAML.load_file(SUGGESTION_FILE, symbolize_names: true) rescue []
      end
      
      def save_learned_patterns
        FileUtils.mkdir_p(File.dirname(SUGGESTION_FILE))
        File.write(SUGGESTION_FILE, @learned_patterns.to_yaml)
      end
      
      def detect_project_size
        file_count = Dir.glob('**/*.rb').size
        case file_count
        when 0..10 then 'shallow'
        when 11..50 then 'medium'
        else 'deep'
        end
      end
      
      def common_ignores
        %w[vendor node_modules .git tmp log]
      end
      
      def should_run_tests?
        tests_exist? && uncommitted_changes?
      end
      
      def estimate_safe_budget
        file_count = Dir.glob('**/*.rb').size
        file_count < 20 ? 1.0 : 2.0
      end
      
      def estimate_iterations
        file_count = Dir.glob('**/*.rb').size
        [file_count / 5, 10].min
      end
      
      def recommend_models
        %w[strong fast cheap]
      end
      
      def estimate_timeout
        60
      end
      
      def uncommitted_changes?
        system('git status --porcelain 2>/dev/null | grep -q .')
      end
      
      def tests_exist?
        Dir.exist?('test') || Dir.exist?('spec')
      end
      
      def git_repo?
        Dir.exist?('.git')
      end
      
      def directory_large?
        Dir.glob('**/*').size > 1000
      end
      
      def detect_project_type
        return :rails if File.exist?('config/routes.rb')
        return :sinatra if File.exist?('config.ru')
        return :gem if Dir.glob('*.gemspec').any?
        :ruby
      end
    end
    
    # Context analyzer for deeper insights
    class ContextAnalyzer
      def analyze(path = '.')
        {
          file_stats: file_statistics(path),
          git_activity: git_activity(path),
          test_coverage: test_coverage(path),
          complexity: code_complexity(path)
        }
      end
      
      private
      
      def file_statistics(path)
        files = Dir.glob(File.join(path, '**', '*.rb'))
        {
          count: files.size,
          total_lines: files.sum { |f| File.read(f).lines.count rescue 0 },
          avg_size: files.size > 0 ? files.sum { |f| File.size(f) } / files.size : 0
        }
      end
      
      def git_activity(path)
        return nil unless Dir.exist?(File.join(path, '.git'))
        
        commits = `git -C #{path} log --oneline --since='1 week ago' 2>/dev/null`.lines.count
        {
          recent_commits: commits,
          active: commits > 5
        }
      end
      
      def test_coverage(path)
        test_files = Dir.glob(File.join(path, '{test,spec}', '**', '*.rb')).size
        src_files = Dir.glob(File.join(path, 'lib', '**', '*.rb')).size
        
        return nil if src_files.zero?
        
        {
          test_files: test_files,
          coverage_ratio: test_files.to_f / src_files
        }
      end
      
      def code_complexity(path)
        files = Dir.glob(File.join(path, '**', '*.rb'))
        total_complexity = 0
        
        files.each do |file|
          content = File.read(file) rescue next
          # Simple complexity: count conditionals, loops
          complexity = content.scan(/\b(if|unless|while|until|for|case)\b/).size
          total_complexity += complexity
        end
        
        {
          total: total_complexity,
          avg_per_file: files.size > 0 ? total_complexity.to_f / files.size : 0
        }
      end
    end
  end
end
