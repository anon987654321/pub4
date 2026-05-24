# frozen_string_literal: true

require "open3"
require "shellwords"

module Master
  module Now
  module CommandRegistry
    module_function

    def tool_commands(root)
      {
        "postpro" => ->(ctx) { dispatch_master_tool(root:, tool: "postpro", arg: arg_for(ctx)) },
        "repligen" => ->(ctx) { dispatch_master_tool(root:, tool: "repligen", arg: arg_for(ctx)) }
      }
    end

    def dispatch_master_tool(root:, tool:, arg:)
      script = File.join(root, "tools", "#{tool}.rb")
      return "#{tool}: missing tool entrypoint #{script}" unless File.file?(script)

      argv = Shellwords.split(arg.to_s)
      out, status = Open3.capture2e(RbConfig.ruby, script, *argv, chdir: File.expand_path("..", root))
      status.success? ? out.strip : "#{tool}: exit=#{status.exitstatus}\n#{out.strip}"
    rescue ArgumentError => e
      "#{tool}: bad arguments: #{e.message}"
    rescue StandardError => e
      "#{tool}: #{e.class}: #{e.message}"
    end
  end
  end
end
