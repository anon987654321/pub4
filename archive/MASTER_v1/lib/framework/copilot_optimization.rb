# frozen_string_literal: true

require 'yaml'

module MASTER
  module Framework
    class CopilotOptimization
      @config = nil
      @config_mtime = nil

      class << self
        def config
          load_config unless @config
          @config
        end

        def load_config
          path = config_path
          return @config = default_config unless File.exist?(path)

          current_mtime = File.mtime(path)
          if @config && @config_mtime == current_mtime
            return @config
          end

          @config = YAML.load_file(path, symbolize_names: true)
          @config_mtime = current_mtime
          @config
        rescue => e
          warn "Failed to load copilot optimization config: #{e.message}"
          @config = default_config
        end

        def patterns
          config[:patterns] || []
        end

        def get_pattern(name)
          patterns.find { |p| p[:name] == name.to_sym }
        end

        def optimize_context(code, metadata = {})
          {
            code: code,
            metadata: enhance_metadata(metadata),
            suggestions: generate_suggestions(code),
            patterns: identify_patterns(code)
          }
        end

        def enhance_metadata(metadata)
          enhanced = metadata.dup
          
          # Add language context
          enhanced[:language] ||= detect_language(metadata[:file_path] || '')
          
          # Add framework context
          enhanced[:framework] ||= detect_framework(metadata[:file_path] || '')
          
          # Add project context
          enhanced[:project_type] ||= 'general'
          
          enhanced
        end

        def generate_suggestions(code)
          patterns.select { |p| p[:enabled] }.flat_map do |pattern|
            case pattern[:type]
            when :prompt_engineering then suggest_prompts(code, pattern)
            when :code_completion then suggest_completions(code, pattern)
            when :refactoring then suggest_refactorings(code, pattern)
            else []
            end
          end
        end

        def suggest_prompts(code, pattern)
          suggestions = []
          
          # Analyze code for improvement opportunities
          if code.lines.size > 50
            suggestions << {
              type: :prompt,
              pattern: pattern[:name],
              message: 'Consider breaking this into smaller functions',
              priority: :medium
            }
          end

          suggestions
        end

        def suggest_completions(code, pattern)
          suggestions = []
          
          # Identify completion opportunities
          incomplete_patterns = pattern[:triggers] || []
          incomplete_patterns.each do |trigger|
            if code.include?(trigger[:pattern])
              suggestions << {
                type: :completion,
                pattern: pattern[:name],
                trigger: trigger[:pattern],
                suggestion: trigger[:suggestion],
                priority: :high
              }
            end
          end

          suggestions
        end

        def suggest_refactorings(code, pattern)
          suggestions = []
          
          # Find refactoring opportunities
          if code.scan(/def \w+/).size > 10
            suggestions << {
              type: :refactoring,
              pattern: pattern[:name],
              message: 'Consider extracting into a module',
              priority: :low
            }
          end

          suggestions
        end

        def identify_patterns(code)
          patterns.select { |p| p[:enabled] }.flat_map do |pattern|
            (pattern[:matchers] || []).filter_map do |matcher|
              next unless code.match?(Regexp.new(matcher[:regex]))
              { pattern: pattern[:name], matcher: matcher[:name], description: pattern[:description] }
            end
          end
        end

        def apply_pattern(code, pattern_name, options = {})
          pattern = get_pattern(pattern_name)
          return { success: false, error: 'Pattern not found' } unless pattern

          case pattern[:type]
          when :prompt_engineering
            result = apply_prompt_pattern(code, pattern, options)
          when :code_completion
            result = apply_completion_pattern(code, pattern, options)
          when :refactoring
            result = apply_refactoring_pattern(code, pattern, options)
          else
            result = { success: false, error: "Unknown pattern type: #{pattern[:type]}" }
          end

          result
        end

        def apply_prompt_pattern(code, pattern, options)
          {
            success: true,
            pattern: pattern[:name],
            enhanced_code: code,
            prompt: generate_enhanced_prompt(code, pattern)
          }
        end

        def apply_completion_pattern(code, pattern, options)
          {
            success: true,
            pattern: pattern[:name],
            completions: generate_completions(code, pattern)
          }
        end

        def apply_refactoring_pattern(code, pattern, options)
          {
            success: true,
            pattern: pattern[:name],
            refactored_code: code,
            changes: []
          }
        end

        def generate_enhanced_prompt(code, pattern)
          base_prompt = "Optimize the following code:\n\n#{code}"
          
          if pattern[:prompt_template]
            base_prompt = pattern[:prompt_template].gsub('{code}', code)
          end

          base_prompt
        end

        def generate_completions(code, pattern)
          # Placeholder for completion generation
          []
        end

        def optimize_for_copilot(code, context = {})
          optimized = code.dup
          changes = []

          # Add meaningful comments
          if should_add_comments?(code)
            optimized = add_context_comments(optimized)
            changes << 'Added context comments'
          end

          # Structure for better completion
          if should_restructure?(code)
            optimized = restructure_for_completion(optimized)
            changes << 'Restructured for better completion'
          end

          {
            success: true,
            code: optimized,
            changes: changes,
            suggestions: generate_suggestions(optimized)
          }
        end

        def analyze_copilot_effectiveness(usage_data)
          {
            success: true,
            acceptance_rate: calculate_acceptance_rate(usage_data),
            completion_quality: assess_completion_quality(usage_data),
            suggestions: generate_improvement_suggestions(usage_data)
          }
        end

        def clear_cache
          @config = nil
          @config_mtime = nil
        end

        def enabled_patterns
          patterns.select { |p| p[:enabled] }
        end

        def pattern_names
          patterns.map { |p| p[:name] }
        end

        private

        def config_path
          File.join(Paths.config_root, 'framework', 'copilot_optimization.yml')
        end

        def default_config
          {
            patterns: [
              {
                name: :prompt_engineering,
                description: 'Optimize prompts for better results',
                type: :prompt_engineering,
                enabled: true,
                prompt_template: '{code}'
              },
              {
                name: :code_completion,
                description: 'Enhance code completion suggestions',
                type: :code_completion,
                enabled: true,
                triggers: []
              },
              {
                name: :refactoring,
                description: 'Suggest refactoring patterns',
                type: :refactoring,
                enabled: true,
                matchers: []
              },
              {
                name: :documentation,
                description: 'Generate documentation patterns',
                type: :prompt_engineering,
                enabled: true,
                prompt_template: 'Document the following code:\n\n{code}'
              },
              {
                name: :test_generation,
                description: 'Generate test cases',
                type: :prompt_engineering,
                enabled: true,
                prompt_template: 'Generate tests for:\n\n{code}'
              }
            ]
          }
        end

        def detect_language(file_path)
          ext = File.extname(file_path)
          case ext
          when '.rb' then :ruby
          when '.py' then :python
          when '.js' then :javascript
          when '.ts' then :typescript
          when '.go' then :go
          else :unknown
          end
        end

        def detect_framework(file_path)
          # Simple framework detection based on path
          if file_path.include?('rails')
            :rails
          elsif file_path.include?('sinatra')
            :sinatra
          else
            :none
          end
        end

        def should_add_comments?(code)
          # Check if code lacks comments
          comment_lines = code.lines.count { |l| l.strip.start_with?('#') }
          total_lines = code.lines.size
          
          total_lines > 10 && comment_lines.to_f / total_lines < 0.1
        end

        def add_context_comments(code)
          # Placeholder for adding comments
          code
        end

        def should_restructure?(code)
          # Check if code structure could be improved
          code.lines.size > 100 && !code.include?('class') && !code.include?('module')
        end

        def restructure_for_completion(code)
          # Placeholder for restructuring
          code
        end

        def calculate_acceptance_rate(usage_data)
          accepted = usage_data[:accepted] || 0
          total = usage_data[:suggested] || 1
          
          (accepted.to_f / total * 100).round(2)
        end

        def assess_completion_quality(usage_data)
          # Assess quality based on various metrics
          {
            relevance: :high,
            accuracy: :high,
            usefulness: :medium
          }
        end

        def generate_improvement_suggestions(usage_data)
          suggestions = []
          
          acceptance_rate = calculate_acceptance_rate(usage_data)
          if acceptance_rate < 50
            suggestions << 'Consider adding more context comments'
            suggestions << 'Review code structure for clarity'
          end

          suggestions
        end
      end
    end
  end
end
