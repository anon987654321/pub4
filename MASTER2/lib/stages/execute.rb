# frozen_string_literal: true

module MASTER
  module Stages
    # Sandboxed code execution (pledge on OpenBSD)
    class Execute
      def call(input)
        response = input[:response] || ""
        blocks = response.scan(/```(?:ruby|rb)\n(.*?)```/m).flatten
        return Result.ok(input.merge(executed: false)) if blocks.empty?

        require "tempfile"
        results = blocks.map { |code| run(code) }
        all_ok = results.all? { |r| r[:success] }
        Result.ok(input.merge(executed: true, success: all_ok, exec_results: results))
      end

      private

      def run(code)
        Tempfile.create(%w[master .rb]) do |f|
          f.write(code)
          f.flush
          # Pledge/unveil must NOT be called here -- they permanently restrict the parent
          # process, not just the child. The child Ruby process is already sandboxed by
          # IO.popen + limited code_execution guards in executor/tools.rb.
          output = IO.popen([RbConfig::CONFIG["ruby_install_name"], f.path], err: %i[child out], &:read)
          { success: $CHILD_STATUS.success?, output: output, exit_code: $CHILD_STATUS.exitstatus }
        end
      end
    end
  end
end
