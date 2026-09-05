# frozen_string_literal: true

require "date"

module Master
  # YAML loading, validation, and rule-shard composition for Master.*.
  module MasterData
    # This ENOENT warning is load-bearing — keep it. A doubled path segment in
    # RuntimeCatalog#web_boot_payload_minimal ("OPENBSD/openbsd/vm_resource.yml")
    # was found only because every load printed "No such file or directory"
    # before quietly defaulting. Callers for whom absence is a legitimate answer
    # should check existence themselves rather than ask this method to go quiet
    # (see load_rules); the signature stays fixed because several tests stub
    # this method, and a new keyword here raises ArgumentError inside the stub.
    def load_yaml(path, symbolize_names: false, default: {})
      raise "yaml too large: #{path}" if File.exist?(path) && File.size(path) > MAX_CONSTITUTION_BYTES

      Timeout.timeout(YAML_LOAD_TIMEOUT_S) do
        YAML.safe_load_file(path, aliases: true, symbolize_names:, permitted_classes: [Date, Time]) || default
      end
    rescue Errno::ENOENT, Errno::EACCES => e
      warn("load_yaml: #{e.message}")
      default
    rescue Psych::Exception, Timeout::Error => e
      warn("load_yaml: #{path}: #{e.message}")
      raise
    end

    # A data file read from a caller's own root, falling back to the one this
    # runtime ships, and never raising at the caller. PrincipleMap and
    # MaturityScorecard each wrote this seven-line shape out, differing only in
    # the filename and the Swallow context — the DRY detector named the pair.
    def load_data_yaml(root, name, fallback, context:)
      path = File.join(root, "data", name)
      path = fallback unless File.file?(path)
      load_yaml(path, default: {}) || {}
    rescue StandardError => e
      Master::Ground::Swallow.log(e, context:)
      {}
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

    # Scanners call this with whatever directory they are scanning
    # (RuleRegistryAudit, SelfTest, YamlBridgeRules, Fix::Priority all pass
    # root: @root). For any root but our own, "this project has no rules.yml" is
    # the answer, not a fault — so absence is quiet there and stays loud for
    # ROOT, where a missing constitution is a real failure. Before this, every
    # scanner test against a Dir.mktmpdir root printed
    # "load_yaml: No such file or directory ... /T/d2026…/data/rules.yml", which
    # trained readers to scroll past the one warning that has already caught a
    # genuine path bug.
    def load_rules(root: ROOT)
      own_root = root == ROOT
      data_dir = own_root ? DATA : File.join(root, "data")
      rules_path = File.join(data_dir, "rules.yml")
      # Skip the read entirely rather than let load_yaml warn — see above.
      return {} unless own_root || File.exist?(rules_path)

      load_yaml(rules_path)
    end

    # The directories MASTER's self-directed gates scan, from
    # data/scan_coverage.yml instead of a path literal repeated in each gate.
    #
    # `File.join(root, "lib")` was written into Fix::SelfCheck and rake
    # constitution, and core/ therefore sat outside the law for three weeks
    # without anyone choosing that. A literal cannot be audited; a manifest can,
    # and rake lint:scan_coverage audits this one. Foreign roots (scanner tests
    # against a mktmpdir) have no manifest and get the old default.
    def scan_roots(root: ROOT)
      data_dir = root == ROOT ? DATA : File.join(root, "data")
      path = File.join(data_dir, "scan_coverage.yml")
      return ["lib"] unless File.exist?(path)

      roots = load_yaml(path).dig("scan_coverage", "roots")
      roots.is_a?(Array) && !roots.empty? ? roots : ["lib"]
    end

    private

    def data_validation_cache
      @data_validation_cache ||= {}
    end

    def yaml_errors(paths, root)
      paths.each_with_object({}) do |path, errors|
        # Same permitted classes as load_yaml — a file that loads must also
        # validate, or a legitimate Date (data/recovery/legacy_manifest.yml)
        # reads as a boot error on every start while loading fine.
        YAML.safe_load_file(path, aliases: true, permitted_classes: [Date, Time])
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
  end
end
