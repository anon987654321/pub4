# frozen_string_literal: true

require 'yaml'

module MASTER
  module Plugins
    class AIEnhancement
      @config = nil
      @config_mtime = nil
      @enabled = false

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
          warn "Failed to load AI enhancement config: #{e.message}"
          @config = default_config
        end

        def config_path
          File.join(__dir__, '..', 'config', 'plugins', 'ai_enhancement.yml')
        end

        def default_config
          {
            enabled: false,
            llm_optimization: { temperature_tuning: true, token_management: true, caching: true },
            prompt_engineering: { templates: true, chain_of_thought: true, few_shot: true, system_prompts: true },
            model_selection: { auto_routing: true, fallback: true, cost_optimization: true },
            context_management: { window_size: 8000, summarization: true, prioritization: true },
            quality_control: { validation: true, consistency_check: true, hallucination_detection: true },
            performance: { batch_processing: true, parallel_requests: true, rate_limiting: true }
          }
        end

        def enabled?
          @enabled
        end

        def enable
          @enabled = true
          load_config
          validate
        end

        def disable
          @enabled = false
        end

        def configure(options = {})
          load_config
          @config = @config.merge(options)
          validate
        end

        def apply(context = {})
          return { success: false, error: 'Plugin not enabled' } unless enabled?

          results = []
          
          # Apply LLM optimization
          if config[:llm_optimization]
            results << apply_llm_optimization(context)
          end

          # Apply prompt engineering
          if config[:prompt_engineering]
            results << apply_prompt_engineering(context)
          end

          # Apply model selection
          if config[:model_selection]
            results << apply_model_selection(context)
          end

          # Apply context management
          if config[:context_management]
            results << apply_context_management(context)
          end

          # Apply quality control
          if config[:quality_control]
            results << apply_quality_control(context)
          end

          # Apply performance optimization
          if config[:performance]
            results << apply_performance(context)
          end

          {
            success: true,
            applied: results.compact,
            timestamp: Time.now
          }
        rescue => e
          { success: false, error: e.message }
        end

        def validate
          errors = []

          # Validate LLM optimization config
          if config[:llm_optimization]
            errors << 'LLM optimization must be a hash' unless config[:llm_optimization].is_a?(Hash)
          end

          # Validate prompt engineering config
          if config[:prompt_engineering]
            errors << 'Prompt engineering must be a hash' unless config[:prompt_engineering].is_a?(Hash)
          end

          # Validate model selection config
          if config[:model_selection]
            errors << 'Model selection must be a hash' unless config[:model_selection].is_a?(Hash)
          end

          # Validate context management config
          if config[:context_management]
            errors << 'Context management must be a hash' unless config[:context_management].is_a?(Hash)
            if config[:context_management][:window_size]
              size = config[:context_management][:window_size]
              errors << 'Window size must be positive' unless size.is_a?(Numeric) && size > 0
            end
          end

          # Validate quality control config
          if config[:quality_control]
            errors << 'Quality control must be a hash' unless config[:quality_control].is_a?(Hash)
          end

          # Validate performance config
          if config[:performance]
            errors << 'Performance must be a hash' unless config[:performance].is_a?(Hash)
          end

          if errors.any?
            { valid: false, errors: errors }
          else
            { valid: true }
          end
        end

        def llm_optimization_config
          config[:llm_optimization] || {}
        end

        def optimize_parameters(task_type, constraints = {})
          params = {
            temperature: default_temperature(task_type),
            max_tokens: constraints[:max_tokens] || 2000,
            top_p: 0.9,
            frequency_penalty: 0.0,
            presence_penalty: 0.0
          }

          if llm_optimization_config[:temperature_tuning]
            params[:temperature] = tune_temperature(task_type, constraints)
          end

          if llm_optimization_config[:token_management]
            params[:max_tokens] = optimize_token_limit(constraints)
          end

          params
        end

        def estimate_cost(model, input_tokens, output_tokens)
          pricing = {
            'gpt-4': { input: 0.03, output: 0.06 },
            'gpt-3.5-turbo': { input: 0.0015, output: 0.002 },
            'claude-3-opus': { input: 0.015, output: 0.075 },
            'claude-3-sonnet': { input: 0.003, output: 0.015 }
          }

          model_key = model.to_sym
          return 0 unless pricing[model_key]

          input_cost = (input_tokens / 1000.0) * pricing[model_key][:input]
          output_cost = (output_tokens / 1000.0) * pricing[model_key][:output]

          {
            input_tokens: input_tokens,
            output_tokens: output_tokens,
            input_cost: input_cost.round(4),
            output_cost: output_cost.round(4),
            total_cost: (input_cost + output_cost).round(4),
            model: model
          }
        end

        def prompt_engineering_config
          config[:prompt_engineering] || {}
        end

        def build_prompt(template_name, variables = {})
          return nil unless prompt_engineering_config[:templates]

          template = get_template(template_name)
          return nil unless template

          prompt = template[:content].dup
          variables.each do |key, value|
            prompt.gsub!("{{#{key}}}", value.to_s)
          end

          {
            template: template_name,
            prompt: prompt,
            variables: variables,
            techniques: extract_techniques(template)
          }
        end

        def apply_chain_of_thought(prompt)
          return prompt unless prompt_engineering_config[:chain_of_thought]

          cot_prefix = "Let's approach this step by step:\n\n"
          cot_suffix = "\n\nPlease show your reasoning for each step."

          cot_prefix + prompt + cot_suffix
        end

        def apply_few_shot(prompt, examples = [])
          return prompt unless prompt_engineering_config[:few_shot]
          return prompt if examples.empty?

          few_shot_section = "Here are some examples:\n\n"
          examples.each_with_index do |ex, i|
            few_shot_section += "Example #{i + 1}:\n"
            few_shot_section += "Input: #{ex[:input]}\n"
            few_shot_section += "Output: #{ex[:output]}\n\n"
          end

          few_shot_section + "Now, please process the following:\n\n" + prompt
        end

        def create_system_prompt(role, constraints = {})
          return nil unless prompt_engineering_config[:system_prompts]

          base = "You are a #{role}."
          
          if constraints[:tone]
            base += " Your tone should be #{constraints[:tone]}."
          end

          if constraints[:format]
            base += " Respond in #{constraints[:format]} format."
          end

          if constraints[:rules]
            base += " Follow these rules: #{constraints[:rules].join(', ')}."
          end

          base
        end

        def model_selection_config
          config[:model_selection] || {}
        end

        def select_model(task_type, constraints = {})
          return nil unless model_selection_config[:auto_routing]

          model_map = {
            code_generation: 'gpt-4',
            code_review: 'gpt-4',
            text_generation: 'gpt-3.5-turbo',
            summarization: 'gpt-3.5-turbo',
            analysis: 'gpt-4',
            creative: 'claude-3-opus',
            conversation: 'gpt-3.5-turbo'
          }

          selected = model_map[task_type.to_sym] || 'gpt-3.5-turbo'

          if constraints[:budget] == 'low'
            selected = 'gpt-3.5-turbo'
          end

          if constraints[:quality] == 'high'
            selected = 'gpt-4'
          end

          {
            model: selected,
            task_type: task_type,
            reasoning: "Selected based on task type and constraints",
            fallback: model_selection_config[:fallback] ? fallback_model(selected) : nil
          }
        end

        def fallback_model(primary_model)
          fallbacks = {
            'gpt-4': 'gpt-3.5-turbo',
            'claude-3-opus': 'claude-3-sonnet',
            'gpt-3.5-turbo': 'gpt-3.5-turbo'
          }
          
          fallbacks[primary_model.to_sym]
        end

        def context_management_config
          config[:context_management] || {}
        end

        def manage_context(messages, max_tokens = nil)
          max_tokens ||= context_management_config[:window_size] || 8000
          
          total_tokens = estimate_tokens(messages)
          
          if total_tokens <= max_tokens
            return { messages: messages, tokens: total_tokens, truncated: false }
          end

          if context_management_config[:summarization]
            messages = summarize_messages(messages, max_tokens)
          elsif context_management_config[:prioritization]
            messages = prioritize_messages(messages, max_tokens)
          else
            messages = truncate_messages(messages, max_tokens)
          end

          {
            messages: messages,
            tokens: estimate_tokens(messages),
            truncated: true,
            strategy: determine_strategy
          }
        end

        def quality_control_config
          config[:quality_control] || {}
        end

        def validate_response(response, criteria = {})
          return { valid: true } unless quality_control_config[:validation]

          validations = []

          if criteria[:min_length]
            valid = response.length >= criteria[:min_length]
            validations << { check: 'min_length', passed: valid }
          end

          if criteria[:format]
            valid = check_format(response, criteria[:format])
            validations << { check: 'format', passed: valid }
          end

          if quality_control_config[:consistency_check]
            valid = check_consistency(response)
            validations << { check: 'consistency', passed: valid }
          end

          if quality_control_config[:hallucination_detection]
            valid = detect_hallucination(response, criteria[:context])
            validations << { check: 'hallucination', passed: valid }
          end

          all_passed = validations.all? { |v| v[:passed] }

          {
            valid: all_passed,
            validations: validations,
            response: response
          }
        end

        def performance_config
          config[:performance] || {}
        end

        def optimize_batch(requests)
          return requests unless performance_config[:batch_processing]

          {
            batches: group_requests(requests),
            strategy: 'batch_processing',
            estimated_time: estimate_batch_time(requests)
          }
        end

        private

        def apply_llm_optimization(context)
          {
            type: 'llm_optimization',
            data: llm_optimization_config,
            parameters: optimize_parameters(context[:task_type] || 'general', context[:constraints] || {}),
            applied_to: context[:target] || 'model'
          }
        end

        def apply_prompt_engineering(context)
          {
            type: 'prompt_engineering',
            data: prompt_engineering_config,
            techniques: prompt_engineering_config.keys.select { |k| prompt_engineering_config[k] },
            applied_to: context[:target] || 'prompts'
          }
        end

        def apply_model_selection(context)
          {
            type: 'model_selection',
            data: model_selection_config,
            selection: select_model(context[:task_type] || 'general', context[:constraints] || {}),
            applied_to: context[:target] || 'routing'
          }
        end

        def apply_context_management(context)
          {
            type: 'context_management',
            data: context_management_config,
            window_size: context_management_config[:window_size],
            applied_to: context[:target] || 'conversation'
          }
        end

        def apply_quality_control(context)
          {
            type: 'quality_control',
            data: quality_control_config,
            checks: quality_control_config.keys.select { |k| quality_control_config[k] },
            applied_to: context[:target] || 'responses'
          }
        end

        def apply_performance(context)
          {
            type: 'performance',
            data: performance_config,
            optimizations: performance_config.keys.select { |k| performance_config[k] },
            applied_to: context[:target] || 'requests'
          }
        end

        def default_temperature(task_type)
          temps = {
            code_generation: 0.2,
            code_review: 0.3,
            analysis: 0.4,
            creative: 0.8,
            conversation: 0.7,
            summarization: 0.3
          }
          
          temps[task_type.to_sym] || 0.7
        end

        def tune_temperature(task_type, constraints)
          base_temp = default_temperature(task_type)
          
          if constraints[:creativity] == 'high'
            base_temp += 0.2
          elsif constraints[:creativity] == 'low'
            base_temp -= 0.2
          end

          [[base_temp, 0.0].max, 2.0].min
        end

        def optimize_token_limit(constraints)
          max = constraints[:max_tokens] || 2000
          
          if constraints[:response_length] == 'short'
            max = [max, 500].min
          elsif constraints[:response_length] == 'long'
            max = [max, 4000].max
          end

          max
        end

        def get_template(name)
          templates = {
            code_review: {
              content: "Review the following code:\n\n{{code}}\n\nProvide feedback on:",
              techniques: [:structured]
            },
            summarize: {
              content: "Summarize the following text:\n\n{{text}}",
              techniques: [:simple]
            }
          }
          
          templates[name.to_sym]
        end

        def extract_techniques(template)
          template[:techniques] || []
        end

        def estimate_tokens(messages)
          return 0 unless messages.is_a?(Array)
          
          messages.sum do |msg|
            content = msg.is_a?(Hash) ? msg[:content] : msg.to_s
            (content.length / 4.0).ceil
          end
        end

        def summarize_messages(messages, max_tokens)
          messages.take(3)
        end

        def prioritize_messages(messages, max_tokens)
          messages.take(5)
        end

        def truncate_messages(messages, max_tokens)
          messages.take(messages.length / 2)
        end

        def determine_strategy
          if context_management_config[:summarization]
            'summarization'
          elsif context_management_config[:prioritization]
            'prioritization'
          else
            'truncation'
          end
        end

        def check_format(response, format)
          case format
          when 'json'
            begin
              JSON.parse(response)
              true
            rescue StandardError
              false
            end
          when 'markdown'
            response.include?('#') || response.include?('*')
          else
            true
          end
        end

        def check_consistency(response)
          true
        end

        def detect_hallucination(response, context)
          true
        end

        def group_requests(requests)
          requests.each_slice(10).to_a
        end

        def estimate_batch_time(requests)
          (requests.length / 10.0).ceil * 2
        end
      end
    end
  end
end
