# frozen_string_literal: true

module MASTER
  class CLI
    module Features
      module Templates
        # Command templates and workflows
        
        WORKFLOWS = {
          'refactor-flow' => [
            'scan',
            'smells',
            'refactor %{target}',
            'review'
          ],
          'audit-flow' => [
            'scan',
            'audit %{target}',
            'principles',
            'converge'
          ],
          'context-query' => [
            'scan',
            'context add %{file}',
            'ask %{query}'
          ],
          'quick-review' => [
            'diff',
            'review',
            'lint'
          ]
        }.freeze
        
        def list_templates
          # Use constants from the including class
          c_bold = self.class.const_get(:C_BOLD)
          c_light_blue = self.class.const_get(:C_LIGHT_BLUE)
          c_dim = self.class.const_get(:C_DIM)
          c_reset = self.class.const_get(:C_RESET)
          icon_flow = self.class.const_get(:ICON_FLOW)
          
          lines = ["#{c_bold}Available Workflows#{c_reset}"]
          
          WORKFLOWS.each do |name, steps|
            lines << "\n#{c_light_blue}#{name}#{c_reset}"
            steps.each do |step|
              lines << "  #{icon_flow} #{step}"
            end
          end
          
          lines << "\n#{c_dim}Usage: workflow <name> [args...]#{c_reset}"
          lines.join("\n")
        end
        
        def run_workflow(name, args = {})
          workflow = WORKFLOWS[name]
          return "Unknown workflow: #{name}" unless workflow
          
          # Use constants from the including class
          c_dim = self.class.const_get(:C_DIM)
          c_reset = self.class.const_get(:C_RESET)
          
          # Parse args
          params = parse_workflow_args(args)
          
          results = []
          workflow.each_with_index do |step, idx|
            # Substitute parameters
            command = step % params.transform_keys(&:to_sym)
            
            puts "#{c_dim}[#{idx + 1}/#{workflow.size}] #{command}#{c_reset}"
            
            begin
              result = handle(command)
              results << result if result
            rescue => e
              results << error_with_solution(e)
              break  # Stop workflow on error
            end
          end
          
          results.join("\n\n")
        end
        
        def save_custom_workflow(name, steps)
          @custom_workflows ||= {}
          @custom_workflows[name] = steps
          "Workflow '#{name}' saved"
        end
        
        private
        
        def parse_workflow_args(args)
          # Simple key=value parsing
          parsed = {}
          args = args.to_s.split if args.is_a?(String)
          
          args.each do |arg|
            key, value = arg.split('=', 2)
            parsed[key] = value if key && value
          end
          
          # Defaults
          parsed['target'] ||= default_target
          parsed['file'] ||= default_file
          parsed['query'] ||= ''
          
          parsed
        end
      end
    end
  end
end
