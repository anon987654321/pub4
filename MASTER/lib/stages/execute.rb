# frozen_string_literal: true

require "tempfile"

module MASTER
  module Stages
    class Execute
      def call(input)
        response = input[:response] || input["response"] || ""
        
        # Extract Ruby code blocks
        code_blocks = extract_ruby_blocks(response)
        
        return Result.ok(input.merge(executed: false, results: [])) if code_blocks.empty?
        
        results = []
        
        code_blocks.each do |code|
          result = execute_ruby(code)
          results << result
        end
        
        Result.ok(input.merge(
          executed: true,
          success: results.all? { |r| r[:success] },
          results: results
        ))
      end

      private

      def extract_ruby_blocks(text)
        blocks = []
        text.scan(/```ruby\n(.*?)```/m) do |match|
          blocks << match[0]
        end
        blocks
      end

      def execute_ruby(code)
        Tempfile.create(["execute", ".rb"]) do |file|
          file.write(code)
          file.flush
          
          # Try to apply pledge if on OpenBSD
          begin
            if Pledge.available?
              Pledge.unveil(file.path, "r")
              Pledge.unveil("/usr/lib", "r")
              Pledge.unveil("/usr/local/lib", "r")
              Pledge.lock_unveil
              Pledge.pledge("stdio rpath")
            end
          rescue Pledge::PledgeError
            # Continue without sandbox on non-OpenBSD
          end
          
          # Execute with IO.popen (no shell interpolation)
          output = ""
          status = nil
          
          IO.popen(["ruby", file.path], err: [:child, :out]) do |io|
            output = io.read
            io.close
            status = $?
          end
          
          {
            success: status.success?,
            output: output,
            exit_code: status.exitstatus
          }
        end
      rescue => e
        {
          success: false,
          output: "",
          error: e.message
        }
      end
    end
  end
end
