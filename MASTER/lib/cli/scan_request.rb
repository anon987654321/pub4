# frozen_string_literal: true

require "set"

module Master
  module CLI
    class ScanRequest
      EXPLICIT_PROFILE_FLAG = "--profile"
      ALL_RULES = "*"
      EMPTY_WORKFLOW_PROFILES = [{}, {}].freeze
      # Path aliases so MASTER can target pub4/RAILS and face without ceremony.
      TARGET_ALIASES = {
        "rails" => Master::RAILS_ROOT,
        "RAILS" => Master::RAILS_ROOT,
        "face" => File.join(Master::ROOT, "web", "public"),
        "web" => File.join(Master::ROOT, "web"),
        "master" => Master::ROOT,
        "self" => File.join(Master::ROOT, "lib"),
      }.freeze

      Result = Struct.new(:pairs, :profile, :rule_filter, :severity_filter, keyword_init: true)

      def initialize(scanner:, root:, arg:, depth: :deep, autofix: false)
        @scanner = scanner
        @root = root
        @arg = arg.to_s.strip
        @depth = depth
        @autofix = autofix
      end

      def call
        @profile, @rule_filter, @severity_filter = resolve_profile
        Result.new(pairs: collect_pairs, profile: @profile, rule_filter: @rule_filter, severity_filter: @severity_filter)
      end

      private

      attr_reader :scanner, :root, :arg, :depth, :autofix, :rule_filter

      def collect_pairs
        target = target_arg
        return file_pairs(target) if target && File.file?(target)
        # A target that was asked for and does not resolve must not quietly
        # become the root — that fallback is how `/scan ../RAILS` measured
        # MASTER and called it RAILS. bin/gate reads this prefix as
        # inconclusive, which is what an unmeasured stage is.
        return "scan failed: no such target: #{target}" if target && !File.directory?(target)

        dir = target || root
        scan_dir = scanner.scan_dir(
          dir, depth:, glob: "**/*", stream: true,
          autofix:, autofix_root: root, rules: selected_rules
        )
        scan_dir.ok? ? scan_dir.value! : "scan failed"
      end

      # One file is the same contract as a directory walk: scan, and if autofix
      # is on, write the mechanical transforms before the caller sees the pair.
      def file_pairs(target)
        result = scanner.scan(target, depth:, rules: selected_rules)
        if autofix && scanner.respond_to?(:autofix_one)
          applied = scanner.autofix_one(target, result, root:)
          result = scanner.scan(target, depth:, rules: selected_rules) if applied.any?
        end
        [[target, result]]
      end

      # limits.yml said profiles "filter the report". The walk still ran every
      # rule, so `/through aesthetic master` spent hours on CONFIG_HIERARCHY.
      # The filter is the walk: the report then describes what actually ran.
      def selected_rules
        return unless rule_filter && scanner.respond_to?(:rules)

        scanner.rules.select { |rule| rule_filter.include?(rule.id.to_s) }
      end

      def target_arg
        raw = raw_target_arg
        return if raw.empty?

        expand_scan_target(raw)
      end

      def expand_scan_target(raw)
        return TARGET_ALIASES[raw] if TARGET_ALIASES.key?(raw)
        if raw.match?(%r{\Arails[:/]}i)
          rest = raw.sub(%r{\Arails[:/]}i, "")
          return File.join(Master::RAILS_ROOT, rest)
        end
        if raw.match?(%r{\ARAILS/})
          return File.expand_path(raw, Master::REPO_ROOT)
        end

        File.expand_path(raw)
      end

      def raw_target_arg
        parts = arg_parts.dup
        return parts[2..]&.join(" ").to_s.strip if parts.first == EXPLICIT_PROFILE_FLAG
        # A word can name both a scan profile and a target — "rails" is a
        # limits.yml profile AND pub4/RAILS. When it names both, it is the
        # target: reading `/scan rails` as "scan MASTER with the rails
        # ruleset" sent the gate's whole deploy stage back over MASTER.
        # requested_profile still sees the word, so the rails tree is scanned
        # under the rails profile, which is the only reading that uses both.
        return parts[1..]&.join(" ").to_s.strip if profile_keyword?(parts.first) && !target_word?(parts.first)

        arg
      end

      def target_word?(word)
        return false if word.to_s.empty?

        TARGET_ALIASES.key?(word) || word.include?("/") || File.exist?(File.expand_path(word))
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
        return if normalized.empty?
        profile_alias_index(profiles)[normalized]
      end

      def arg_parts
        arg.split(/\s+/)
      end

      def load_workflow_profiles
        path = Master.limits_path
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
        @workflow_profiles_cache[path] = { mtime:, value: }
        value
      rescue StandardError
        EMPTY_WORKFLOW_PROFILES
      end

      def profile_alias_index(profiles)
        @profile_alias_index ||= {}
        cache_key = profiles.object_id
        cached = @profile_alias_index[cache_key]
        return cached if cached

        @profile_alias_index[cache_key] = profiles.each_with_object({}) do |(profile, cfg), index|
          next unless cfg.is_a?(Hash)

          index[profile.to_s] = profile.to_s
          Array(cfg["aliases"]).each { |name| index[name.to_s] = profile.to_s }
        end
      end
    end
  end
end
