# frozen_string_literal: true

module Master
  # YAML loading, validation, and rule-shard composition for Master.*.
  module MasterData
    def load_yaml(path, symbolize_names: false, default: {})
      raise "yaml too large: #{path}" if File.exist?(path) && File.size(path) > MAX_CONSTITUTION_BYTES

      Timeout.timeout(YAML_LOAD_TIMEOUT_S) do
        YAML.safe_load_file(path, aliases: true, symbolize_names:) || default
      end
    rescue Psych::Exception, Errno::ENOENT, Errno::EACCES => e
      warn("load_yaml: #{e.message}")
      default
    rescue Timeout::Error => e
      warn("load_yaml: #{path}: #{e.message}")
      default
    end

    def validate_data!(root: ROOT, bus: nil)
      paths = Dir.glob(File.join(root, "data", "**/*.yml")).sort
      signature = paths.to_h { |path| [path, File.mtime(path).to_i] }
      cached = data_validation_cache[root]
      return cached[:errors] if cached && cached[:signature] == signature

      errors = yaml_errors(paths, root)
      data_validation_cache[root] = { signature:, errors: }
      publish_yaml_errors(errors, bus)
      errors
    end

    def load_rules(root: ROOT)
      data_dir = root == ROOT ? DATA : File.join(root, "data")
      base = load_yaml(File.join(data_dir, "rules.yml"))
      shards = Dir.glob(File.join(data_dir, "rules", "*.yml")).sort
      return base if shards.empty?

      base.merge("rules" => merge_rule_shards(base, shards))
    end

    private

    def data_validation_cache
      @data_validation_cache ||= {}
    end

    def yaml_errors(paths, root)
      paths.each_with_object({}) do |path, errors|
        YAML.safe_load_file(path, aliases: true)
      rescue Psych::Exception => e
        errors[path.delete_prefix("#{root}/")] = e.message.lines.first.to_s.strip
      end
    end

    def publish_yaml_errors(errors, bus)
      errors.each do |relative, message|
        warn("yaml_validation: #{relative}: #{message}")
        bus&.publish("data:yaml_parse_error", path: relative, error: message)
      end
    end

    def merge_rule_shards(base, shards)
      merged = JSON.parse(JSON.generate(base.fetch("rules", {})))
      shards.each do |file|
        (load_yaml(file) || {}).each { |scope, list| (merged[scope] ||= []).concat(Array(list)) }
      end
      merged
    end
  end
end
