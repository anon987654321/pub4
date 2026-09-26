# frozen_string_literal: true

module Deploy
  module OperatorSource
    SOURCE = /^\s*source\s+"\$\{CONFIG_ROOT\}\/lib\/([^"]+)"\s*$/.freeze

    module_function

    def read(path)
      script = File.read(path, encoding: "UTF-8").scrub
      helpers = source_paths(script, path)
      ([script] + helpers.map { |helper| File.read(helper, encoding: "UTF-8").scrub }).join("\n")
    end

    def source_paths(script, path)
      root = File.dirname(path)
      script.scan(SOURCE).flatten.filter_map do |name|
        helper = File.join(root, "lib", name)
        raise "missing operator helper #{helper}" unless File.file?(helper)
        helper
      end.uniq
    end
  end
end
