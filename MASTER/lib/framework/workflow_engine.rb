# frozen_string_literal: true

require 'yaml'

module MASTER
  module Framework
    class WorkflowEngine
      @config = nil
      @config_mtime = nil
      @workflows = {}

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
          warn "Failed to load workflow engine config: #{e.message}"
          @config = default_config
        end

        def workflows
          config[:workflows] || []
        end

        def get_workflow(name)
          workflows.find { |w| w[:name] == name.to_sym }
        end

        def create_workflow(name, definition = {})
          workflow = {
            id: generate_id,
            name: name.to_sym,
            status: :pending,
            created_at: Time.now,
            phases: definition[:phases] || [],
            current_phase: nil,
            context: {},
            results: []
          }

          @workflows[workflow[:id]] = workflow
          workflow
        end

        def execute_workflow(workflow_id, context = {})
          workflow = @workflows[workflow_id]
          return { success: false, error: 'Workflow not found' } unless workflow

          workflow[:status] = :running
          workflow[:context].merge!(context)
          workflow[:started_at] = Time.now

          results = []
          
          workflow[:phases].each do |phase|
            result = execute_phase(phase, workflow[:context])
            results << result

            if result[:success]
              workflow[:current_phase] = phase[:name]
            else
              workflow[:status] = :failed
              workflow[:error] = result[:error]
              workflow[:completed_at] = Time.now
              return {
                success: false,
                workflow_id: workflow_id,
                phase: phase[:name],
                error: result[:error],
                results: results
              }
            end
          end

          workflow[:status] = :completed
          workflow[:completed_at] = Time.now
          workflow[:results] = results

          {
            success: true,
            workflow_id: workflow_id,
            duration: workflow[:completed_at] - workflow[:started_at],
            results: results
          }
        end

        def execute_phase(phase, context)
          phase_result = { phase: phase[:name], started_at: Time.now, steps: [] }

          (phase[:steps] || []).each do |step|
            step_result = execute_step(step, context)
            phase_result[:steps] << step_result

            next if step_result[:success]
            
            phase_result[:success] = false
            phase_result[:error] = step_result[:error]
            phase_result[:completed_at] = Time.now
            return phase_result
          end

          context.merge!(phase_result[:steps].last&.dig(:output) || {})
          phase_result[:success] = true
          phase_result[:completed_at] = Time.now
          phase_result
        end

        def execute_step(step, context)
          step_result = { step: step[:name], type: step[:type], started_at: Time.now }

          output = case step[:type]
                   when :task then execute_task(step, context)
                   when :gate then execute_gate(step, context)
                   when :automation then execute_automation(step, context)
                   when :validation then execute_validation(step, context)
                   else { success: false, error: "Unknown step type: #{step[:type]}" }
                   end

          step_result.merge!(output)
          step_result[:completed_at] = Time.now
          step_result
        rescue StandardError => e
          step_result[:success] = false
          step_result[:error] = e.message
          step_result[:completed_at] = Time.now
          step_result
        end

        def execute_task(step, context)
          # Execute a task step
          {
            success: true,
            output: { task_completed: step[:name] }
          }
        end

        def execute_gate(step, context)
          # Execute a quality gate check
          gate_name = step[:gate]
          {
            success: true,
            output: { gate_passed: gate_name }
          }
        end

        def execute_automation(step, context)
          # Execute automated action
          {
            success: true,
            output: { automation_completed: step[:name] }
          }
        end

        def execute_validation(step, context)
          # Execute validation step
          {
            success: true,
            output: { validation_passed: step[:name] }
          }
        end

        def pause_workflow(workflow_id)
          workflow = @workflows[workflow_id]
          return { success: false, error: 'Workflow not found' } unless workflow

          workflow[:status] = :paused
          workflow[:paused_at] = Time.now
          
          { success: true, workflow_id: workflow_id, status: :paused }
        end

        def resume_workflow(workflow_id)
          workflow = @workflows[workflow_id]
          return { success: false, error: 'Workflow not found' } unless workflow
          return { success: false, error: 'Workflow not paused' } unless workflow[:status] == :paused

          workflow[:status] = :running
          workflow[:resumed_at] = Time.now
          
          { success: true, workflow_id: workflow_id, status: :running }
        end

        def cancel_workflow(workflow_id)
          workflow = @workflows[workflow_id]
          return { success: false, error: 'Workflow not found' } unless workflow

          workflow[:status] = :cancelled
          workflow[:cancelled_at] = Time.now
          
          { success: true, workflow_id: workflow_id, status: :cancelled }
        end

        def get_workflow_status(workflow_id)
          workflow = @workflows[workflow_id]
          return { success: false, error: 'Workflow not found' } unless workflow

          {
            success: true,
            workflow_id: workflow_id,
            name: workflow[:name],
            status: workflow[:status],
            current_phase: workflow[:current_phase],
            progress: calculate_progress(workflow),
            created_at: workflow[:created_at],
            started_at: workflow[:started_at],
            completed_at: workflow[:completed_at]
          }
        end

        def list_workflows(filter = {})
          results = @workflows.values

          if filter[:status]
            results = results.select { |w| w[:status] == filter[:status] }
          end

          if filter[:name]
            results = results.select { |w| w[:name] == filter[:name].to_sym }
          end

          results.map { |w| summarize_workflow(w) }
        end

        def clear_cache
          @config = nil
          @config_mtime = nil
        end

        def clear_workflows
          @workflows = {}
        end

        private

        def config_path
          File.join(Paths.config_root, 'framework', 'workflow_engine.yml')
        end

        def default_config
          {
            workflows: [
              {
                name: :development,
                description: 'Standard development workflow',
                phases: [
                  {
                    name: :planning,
                    steps: [
                      { name: :requirements, type: :task },
                      { name: :design, type: :task }
                    ]
                  },
                  {
                    name: :implementation,
                    steps: [
                      { name: :code, type: :task },
                      { name: :test, type: :task }
                    ]
                  },
                  {
                    name: :validation,
                    steps: [
                      { name: :quality_gate, type: :gate },
                      { name: :review, type: :validation }
                    ]
                  }
                ]
              }
            ]
          }
        end

        def generate_id
          "wf_#{Time.now.to_i}_#{rand(10000)}"
        end

        def calculate_progress(workflow)
          return 0 if workflow[:phases].empty?

          completed_phases = workflow[:results].select { |r| r[:success] }.size
          total_phases = workflow[:phases].size
          
          (completed_phases.to_f / total_phases * 100).round(2)
        end

        def summarize_workflow(workflow)
          {
            id: workflow[:id],
            name: workflow[:name],
            status: workflow[:status],
            progress: calculate_progress(workflow),
            created_at: workflow[:created_at]
          }
        end
      end
    end
  end
end
