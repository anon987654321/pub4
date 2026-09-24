# frozen_string_literal: true

require "date"

module Master
  # YAML loading, validation, and rule-shard composition for Master.*.
  module DataLoading
    # This ENOENT warning is load-bearing — keep it. A doubled path segment in
    # RuntimeCatalog#web_boot_payload_minimal ("OPENBSD/openbsd/vm_resource.yml")
    # was found only because every load printed "No such file or directory"
    # before quietly defaulting. Callers for whom absence is a legitimate answer
    # should check existence themselves rather than ask this method to go quiet
    # (see load_rules); the signature stays fixed because several tests stub
    # this method, and a new keyword here raises ArgumentError inside the stub.
    #
    # Parses are remembered by path, size, inode and mtime, and every call gets
    # its own copy. rules.yml is 205KB and fifteen constructors read it: one
    # boot and a /scan of lib/io parsed it 40 times for 724ms. A deep copy of
    # the parsed tree costs a fraction of a parse and cannot leak one caller's
    # mutation into another's, and an edit changes the stat, so the next read
    # parses again. The copy is walked by hand, because this tree forbids
    # deserialising with Marshal anywhere in lib/.
    def load_yaml(path, symbolize_names: false, default: {})
      stat = File.stat(path)
      raise "yaml too large: #{path}" if stat.size > MAX_CONSTITUTION_BYTES

      key = [File.expand_path(path), symbolize_names, stat.size, stat.ino, stat.mtime.to_r]
      parsed = yaml_parse_cache[key] ||= Timeout.timeout(YAML_LOAD_TIMEOUT_S) do
        yaml_deep_freeze(YAML.safe_load_file(path, aliases: true, symbolize_names:, permitted_classes: [Date, Time]))
      end
      yaml_copy(parsed) || default
    rescue Errno::ENOENT, Errno::EACCES => e
      warn_unreadable_once(path, e)
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
      raise "data file missing: #{path}" unless File.file?(path)

      data = load_yaml(path)
      raise "data file #{name} is not a hash: #{path}" unless data.is_a?(Hash)

      data
    rescue StandardError => e
      Master::Ground::Swallow.log(e, context:)
      raise "data file unreadable: #{name}: #{e.class}: #{e.message}"
    end
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

    # Once per path. A scan rule reads its optional file once per scanned file,
    # and a missing one would print over the prompt on every read.
    def warn_unreadable_once(path, error)
      key = File.expand_path(path)
      return if yaml_unreadable.key?(key)

      yaml_unreadable[key] = true
      warn("load_yaml: #{error.message}")
    end

    def yaml_unreadable
      @yaml_unreadable ||= {}
    end

    # Key to a frozen parse. Several threads load data files, and ||= on a plain
    # Hash at worst parses one file twice; the cached tree itself is frozen.
    def yaml_parse_cache
      @yaml_parse_cache ||= {}
    end

    # YAML.safe_load yields only hashes, arrays, strings, symbols, numbers,
    # booleans, nil, Date and Time; the containers and strings are what a caller
    # can mutate, so those are what get copied.
    def yaml_copy(value)
      case value
      when Hash then value.each_with_object({}) { |(k, v), out| out[yaml_copy(k)] = yaml_copy(v) }
      when Array then value.map { |item| yaml_copy(item) }
      when String then value.dup
      else value
      end
    end

    def yaml_deep_freeze(value)
      case value
      when Hash then value.each { |k, v| yaml_deep_freeze(k); yaml_deep_freeze(v) }
      when Array then value.each { |item| yaml_deep_freeze(item) }
      end
      value.freeze
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
