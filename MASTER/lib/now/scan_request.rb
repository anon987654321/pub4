# frozen_string_literal: true

require "set"

module Master
  module Now
    class ScanRequest
      EXPLICIT_PROFILE_FLAG = "--profile"
      ALL_RULES = "*"
      EMPTY_WORKFLOW_PROFILES = [{}, {}].freeze

      Result = Struct.new(:pairs, :profile, :rule_filter, :severity_filter, keyword_init: true)

      def initialize(scanner:, root:, arg:, depth: :deep)
        @scanner = scanner
        @root = root
        @arg = arg.to_s.strip
        @depth = depth
      end

      def call
        profile, rule_filter, severity_filter = resolve_profile
        Result.new(pairs: collect_pairs, profile: profile, rule_filter: rule_filter, severity_filter: severity_filter)
      end

      private

      attr_reader :scanner, :root, :arg, :depth

      def collect_pairs
        target = target_arg
        return [[target, scanner.scan(target, depth: depth)]] if target && File.file?(target)

        dir = (target && File.directory?(target)) ? target : root
        scan_dir = scanner.scan_dir(dir, depth: depth, glob: "**/*", stream: true)
        scan_dir.ok? ? scan_dir.value! : "scan failed"
      end

      def target_arg
        raw = raw_target_arg
        raw.empty? ? nil : File.expand_path(raw)
      end

      def raw_target_arg
        parts = arg_parts.dup
        return parts[2..]&.join(" ").to_s.strip if parts.first == EXPLICIT_PROFILE_FLAG
        return parts[1..]&.join(" ").to_s.strip if profile_keyword?(parts.first)

        arg
      end

      def resolve_profile
        groups, profiles = load_workflow_profiles
        profile_name = requested_profile(profiles)
        return [nil, nil, nil] unless profile_name

        cfg = profiles[profile_name] || {}
        rules = cfg["rules"].to_s
        rule_ids = groups[rules] || (rules == ALL_RULES ? nil : [rules])
        rule_filter = (rule_ids && rules != ALL_RULES) ? rule_ids.map(&:to_s).to_set : nil
        severity_filter = Array(cfg["severity"]).map(&:to_s).to_set
        [profile_name, rule_filter, severity_filter.empty? ? nil : severity_filter]
      end

      def requested_profile(profiles)
        parts = arg_parts
        explicit = parts.first == EXPLICIT_PROFILE_FLAG ? parts[1] : nil
        return canonical_profile(explicit, profiles) if explicit

        positional = canonical_profile(parts.first, profiles)
        positional || canonical_profile(profiles["default"], profiles)
      end

      def profile_keyword?(word)
        canonical_profile(word, load_workflow_profiles.last)
      end

      def canonical_profile(name, profiles)
        normalized = name.to_s.strip
        return nil if normalized.empty?
        return normalized if profiles.key?(normalized) && profiles[normalized].is_a?(Hash)

        profiles.find do |_profile, cfg|
          Array(cfg["aliases"]).map(&:to_s).include?(normalized)
        end&.first
      end

      def arg_parts
        arg.split(/\s+/)
      end

      def load_workflow_profiles
        path = File.join(root, "data", "workflow.yml")
        self.class.workflow_profiles(path)
      end

      def self.resolve_scan_profile(arg, root)
        req = allocate
        req.instance_variable_set(:@scanner, nil)
        req.instance_variable_set(:@root, root)
        req.instance_variable_set(:@arg, arg.to_s.strip)
        req.instance_variable_set(:@depth, :deep)
        _, profiles = req.send(:load_workflow_profiles)
        first_word = arg.to_s.strip.split(/\s+/).first
        return [nil, nil, nil] unless req.send(:canonical_profile, first_word, profiles)

        req.send(:resolve_profile)
      end

      def self.workflow_profiles(path)
        @workflow_profiles_cache ||= {}
        mtime = File.mtime(path).to_i
        cached = @workflow_profiles_cache[path]
        return cached[:value] if cached && cached[:mtime] == mtime

        data = Master.load_yaml(path)
        value = [data["principle_groups"] || {}, data["scan_profiles"] || {}]
        @workflow_profiles_cache[path] = { mtime: mtime, value: value }
        value
      rescue StandardError
        EMPTY_WORKFLOW_PROFILES
      end
    end
  end
end
