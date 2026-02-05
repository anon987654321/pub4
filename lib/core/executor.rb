# frozen_string_literal: true

module MASTER
  module Executor
    # Agentic command execution loop
    # Parses LLM responses for code blocks, executes safely, returns output

    SHELL_PATTERN = /```(?:sh|bash|shell|zsh)?\n(.*?)```/m
    RUBY_PATTERN = /```ruby\n(.*?)```/m
    MAX_OUTPUT = 4000

    class << self
      def process_response(response)
        results = []

        # Extract and execute shell commands
        response.scan(SHELL_PATTERN) do |match|
          code = match[0].strip
          next if code.empty?

          result = execute_shell(code)
          results << result if result
        end

        # Extract and execute Ruby code
        response.scan(RUBY_PATTERN) do |match|
          code = match[0].strip
          next if code.empty?

          result = execute_ruby(code)
          results << result if result
        end

        results
      end

      def execute_shell(command)
        # Safety check first
        unless Safety.command_safe?(command)
          return { type: :blocked, command: command, error: "Blocked by safety filter" }
        end

        trace "[exec] #{command[0..60]}..."

        begin
          output = `#{command} 2>&1`
          status = $?.exitstatus

          {
            type: :shell,
            command: command,
            output: truncate(output),
            status: status,
            success: status == 0
          }
        rescue => e
          { type: :shell, command: command, error: e.message, success: false }
        end
      end

      def execute_ruby(code)
        # Safety check
        unless Safety.ruby_safe?(code)
          return { type: :blocked, code: code[0..100], error: "Blocked by safety filter" }
        end

        trace "[ruby] #{code[0..60]}..."

        begin
          # Execute in isolated binding
          result = eval(code, TOPLEVEL_BINDING.dup, "(master)", 1)
          {
            type: :ruby,
            code: code[0..100],
            result: truncate(result.inspect),
            success: true
          }
        rescue => e
          { type: :ruby, code: code[0..100], error: e.message, success: false }
        end
      end

      def format_results(results)
        return nil if results.empty?

        results.map do |r|
          case r[:type]
          when :shell
            status = r[:success] ? "ok" : "err:#{r[:status]}"
            "[#{status}] #{r[:command][0..40]}\n#{r[:output]}"
          when :ruby
            status = r[:success] ? "ok" : "err"
            "[#{status}] ruby: #{r[:result] || r[:error]}"
          when :blocked
            "[blocked] #{r[:error]}"
          end
        end.join("\n\n")
      end

      private

      def truncate(text)
        text.to_s[0..MAX_OUTPUT]
      end

      def trace(msg)
        puts "[    0.#{(Time.now.usec / 1000).to_s.rjust(3, '0')}] #{msg}"
      end
    end
  end
end
