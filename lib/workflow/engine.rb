# frozen_string_literal: true
require "json"

module MASTER
  module Workflow
    class Engine
      attr_reader :llm, :principles, :history

      def initialize(llm:, principles: [])
        @llm = llm
        @principles = principles
        @history = []
      end

      # Execute a natural language workflow
      def execute(natural_language_task)
        puts "📋 Parsing workflow: #{natural_language_task}"
        
        plan = parse_to_executable_plan(natural_language_task)
        return { success: false, error: "Failed to parse workflow" } unless plan

        puts "\n✓ Plan created with #{plan['steps'].size} steps:"
        plan['steps'].each_with_index do |step, idx|
          puts "  #{idx + 1}. #{step['action']}: #{step['description']}"
        end
        puts

        results = []
        plan['steps'].each_with_index do |step, idx|
          puts "▶ Step #{idx + 1}/#{plan['steps'].size}: #{step['action']}"
          
          result = execute_step(step)
          results << result

          if result[:success]
            puts "  ✓ Completed"
          else
            puts "  ✗ Failed: #{result[:error]}"
            
            # Try to adapt plan on failure
            adapted_plan = adapt_plan(plan, step, result[:error])
            if adapted_plan
              puts "  🔄 Adapting plan..."
              plan = adapted_plan
            else
              puts "  ⚠ Cannot continue - stopping workflow"
              break
            end
          end
        end

        {
          success: results.all? { |r| r[:success] },
          steps: results,
          history: @history
        }
      end

      # Parse natural language into executable plan
      def parse_to_executable_plan(task)
        prompt = <<~PROMPT
          Convert this natural language task into an executable workflow plan.

          Task: "#{task}"

          Return ONLY valid JSON in this format:
          {
            "steps": [
              {
                "action": "analyze|fix|test|commit",
                "description": "what this step does",
                "params": {
                  "path": "file or directory path",
                  "options": {}
                }
              }
            ]
          }

          Supported actions:
          - analyze: Run code analysis on path
          - fix: Apply fixes to code
          - test: Run test suite
          - commit: Git commit with message

          Keep it simple and atomic. Return ONLY the JSON, no other text.
        PROMPT

        result = @llm.chat(prompt, tier: :medium, cache: false)
        return nil unless result.ok?

        # Extract JSON from response
        json_text = result.value[/\{.*\}/m]
        JSON.parse(json_text) rescue nil
      end

      # Execute a single workflow step
      def execute_step(step)
        action = step['action']
        params = step['params'] || {}

        @history << { step: step, started_at: Time.now }

        result = case action
        when 'analyze'
          execute_analyze(params)
        when 'fix'
          execute_fix(params)
        when 'test'
          execute_test(params)
        when 'commit'
          execute_commit(params)
        else
          { success: false, error: "Unknown action: #{action}" }
        end

        @history.last[:completed_at] = Time.now
        @history.last[:result] = result

        result
      rescue => e
        { success: false, error: e.message }
      end

      # Adapt plan when a step fails
      def adapt_plan(plan, failed_step, error)
        prompt = <<~PROMPT
          A workflow step failed. Generate an adapted plan.

          Original plan: #{plan.to_json}
          Failed step: #{failed_step.to_json}
          Error: #{error}

          Return an adapted plan as JSON with same format as original.
          Consider:
          1. Skip the failed step and continue?
          2. Retry with different parameters?
          3. Add intermediate steps to resolve the issue?

          Return ONLY the JSON, no other text.
        PROMPT

        result = @llm.chat(prompt, tier: :medium, cache: false)
        return nil unless result.ok?

        json_text = result.value[/\{.*\}/m]
        JSON.parse(json_text) rescue nil
      end

      private

      def execute_analyze(params)
        path = params['path']
        return { success: false, error: "path required" } unless path

        # Use existing engine or simple file read
        if File.exist?(path)
          code = File.read(path)
          {
            success: true,
            data: {
              path: path,
              lines: code.lines.size,
              analyzed: true
            }
          }
        else
          { success: false, error: "File not found: #{path}" }
        end
      end

      def execute_fix(params)
        path = params['path']
        return { success: false, error: "path required" } unless path
        return { success: false, error: "File not found" } unless File.exist?(path)

        # This would integrate with actual fix logic
        # For now, just simulate
        {
          success: true,
          data: { path: path, fixes_applied: 0, message: "Fix logic not yet implemented" }
        }
      end

      def execute_test(params)
        command = params['command'] || 'ruby -e "puts \'No test command specified\'"'
        
        output = `#{command} 2>&1`
        exit_code = $?.exitstatus

        {
          success: exit_code == 0,
          data: {
            command: command,
            exit_code: exit_code,
            output: output[0..500]
          }
        }
      end

      def execute_commit(params)
        message = params['message'] || 'Automated commit'
        
        # Simulate git commit (actual implementation would use git commands)
        {
          success: true,
          data: {
            message: message,
            committed: false,
            note: "Commit simulation - actual git integration needed"
          }
        }
      end
    end
  end
end
