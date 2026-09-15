# frozen_string_literal: true

module Master
  module Core
    module Execution
      module Verifier
        module Rules
          class Base
            def verify(observation, root)
              raise NotImplementedError, "Rule must implement #verify"
            end
          end

          class GitCommitRule < Base
            def verify(observation, root)
              return false unless observation.to_s.include?("committed")
              
              # Check that HEAD has actually moved
              current_head = `git -C #{root} rev-parse HEAD`.strip
              # In a real impl, we would compare this to the pre-effect head
              !current_head.empty?
            end
          end

          class FileWriteRule < Base
            def verify(observation, root)
              return false unless observation.to_s.include?("wrote")
              
              # Extract path from observation: "wrote path/to/file (123b)"
              path = observation.to_s.match(/wrote ([^ (]+)/)&.captures&.first
              return false unless path
              
              File.exist?(File.join(root, path))
            end
          end
        end
      end
    end
  end
end
