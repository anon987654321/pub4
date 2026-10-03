# frozen_string_literal: true

require "open3"
require "rbconfig"
require "shellwords"

module Studio
  module Result
    Item = Data.define(:ok, :value, :message) do
      def ok? = ok
      def err? = !ok
      def value! = value
    end

    module_function

    def ok(value = nil) = Item.new(true, value, nil)
    def err(message) = Item.new(false, nil, message)
  end

  module Paths
    ROOT = File.expand_path("..", __dir__)

    module_function

    def root = ROOT
    def repo = File.expand_path("..", ROOT)
    def tool(name) = File.join(ROOT, name, "#{name}.rb")
  end

  module ScriptDispatch
    module_function

    def run(tool:, arg: "", env: {})
      script = Paths.tool(tool)
      return Result.err("#{tool}: missing tool entrypoint #{script}") unless File.file?(script)

      argv = Shellwords.split(arg.to_s)
      command = env.empty? ? [RbConfig.ruby, script, *argv] : [env.transform_keys(&:to_s).transform_values(&:to_s), RbConfig.ruby, script, *argv]
      stdout, status = Open3.capture2e(*command, chdir: File.dirname(script))
      status.success? ? Result.ok(stdout.strip) : Result.err("#{tool}: exit=#{status.exitstatus}\n#{stdout.strip}")
    rescue ArgumentError => e
      Result.err("#{tool}: bad arguments: #{e.message}")
    rescue StandardError => e
      Result.err("#{tool}: #{e.class}: #{e.message}")
    end
  end
end
