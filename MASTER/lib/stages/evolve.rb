# frozen_string_literal: true

module MASTER
  module Stages
    class Evolve
      def call(input)
        file = input[:file] || input["file"]
        response = input[:response] || input["response"]
        test_command = input[:test_command] || input["test_command"] || "bundle exec ruby -Ilib:test test/"
        
        return Result.err("No file specified for evolution") unless file
        return Result.err("No response provided") unless response
        return Result.err("File does not exist: #{file}") unless File.exist?(file)
        
        # Create git stash
        stash_ref = create_stash
        
        begin
          # Write new content
          File.write(file, response)
          
          # Run tests
          test_result = run_tests(test_command)
          
          if test_result[:success]
            Result.ok(input.merge(
              modified: true,
              tests_passed: true,
              rolled_back: false
            ))
          else
            # Rollback
            rollback_file(file, stash_ref)
            
            Result.ok(input.merge(
              modified: true,
              tests_passed: false,
              rolled_back: true,
              test_output: test_result[:output]
            ))
          end
        rescue => e
          # Rollback on any error
          rollback_file(file, stash_ref) if stash_ref
          Result.err("Evolution failed: #{e.message}")
        end
      end

      private

      def create_stash
        output = ""
        IO.popen(["git", "stash", "create"], err: [:child, :out]) do |io|
          output = io.read.strip
        end
        output.empty? ? nil : output
      end

      def run_tests(command)
        output = ""
        status = nil
        
        # Split command safely
        cmd_parts = command.split(/\s+/)
        
        IO.popen(cmd_parts, err: [:child, :out]) do |io|
          output = io.read
          io.close
          status = $?
        end
        
        {
          success: status.success?,
          output: output,
          exit_code: status.exitstatus
        }
      rescue => e
        {
          success: false,
          output: e.message,
          exit_code: 1
        }
      end

      def rollback_file(file, stash_ref)
        return unless stash_ref
        
        IO.popen(["git", "checkout", stash_ref, "--", file], err: [:child, :out]) do |io|
          io.read
        end
      end
    end
  end
end
