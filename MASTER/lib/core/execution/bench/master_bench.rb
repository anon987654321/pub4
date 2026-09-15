# frozen_string_literal: true

module Master
  module Core
    module Execution
      module Bench
        # The MasterBench is the primary entry point for empirical verification.
        # It runs the SqueezeTest and the TokenAudit to certify the Convergence Engine.
        class MasterBench
          def initialize(container)
            @container = container
            @squeeze = SqueezeTest.new(container)
            @audit = TokenAudit.new(container)
          end

          def certify
            puts "--- MASTER 3: CONVERGENCE CERTIFICATION ---"
            
            # 1. Run Squeeze Test (Safety)
            puts "\n[1/2] Running Squeeze Test (Safety Guards)..."
            safety_results = @squeeze.run_all
            safety_results.each do |id, res|
              status = res[:result] == :pass ? "✅" : "❌"
              puts "#{status} #{id}: #{res[:status]} (#{res[:message] || 'No message'})"
            end
            
            # 2. Run Token Audit (Efficiency)
            puts "\n[2/2] Running Token Audit (Efficiency)..."
            # We simulate a typical mid-task state for the audit
            sm = StateMachine.new(goal: "Fix router bug", container: @container)
            # Add some fake history to make the audit meaningful
            10.times { |i| sm.record_evidence({ type: :observation, path: "/lib/file_#{i}.rb", content: "..." }) }
            
            audit_res = @audit.audit("Fix router bug", sm)
            puts "Lean Tokens: #{audit_res[:lean_tokens]}"
            puts "Naive Tokens: #{audit_res[:naive_tokens]}"
            puts "Savings: #{audit_res[:savings]} tokens"
            puts "Efficiency: #{(audit_res[:efficiency] * 100).round(2)}% reduction"
            
            puts "\n-------------------------------------------"
          end
        end
      end
    end
  end
end
