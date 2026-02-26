# frozen_string_literal: true

module MASTER
  # Scan -- single traversal, pluggable rule modules.
  # THE one interface for all code analysis. Depth controls what runs:
  #
  #   Scan.run("lib/")                     # :quick    -- literal patterns only, no LLM
  #   Scan.run("lib/", depth: :standard)   # :standard -- + structural smells (CodeReview::Engine)
  #   Scan.run("lib/", depth: :hunt)       # :hunt     -- 8-phase bug analysis (BugHunting)
  #   Scan.run("lib/", depth: :critique)   # :critique -- constitutional validation (Violations)
  #   Scan.run("lib/", depth: :deep)       # :deep     -- all of the above + enforcer + plugins
  #
  # Returns: { files: N, total: N, autofix_eligible: N, by_rule: { rule_name => [findings] }, by_file: { path => [findings] } }
  module Scan
    DEPTHS = %i[quick standard hunt critique deep].freeze

    # Namespace for auto-loaded Scan::Rule plugin modules.
    # Files under lib/scan/rules/*.rb are required at :deep depth and must
    # define a module here that responds to .check(code, path:) -> Array<Hash>.
    module Rules; end

    # A Rule is anything that responds to .check(code, path:) -> Array<Hash>
    # Each hash must have: { rule:, message:, line:, severity:, autofix: }
    module Rule
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        def check(_code, path: nil)
          raise NotImplementedError, "#{self}.check(code, path:) not implemented"
        end
      end
    end

    class << self
      def run(path = MASTER.root, depth: :quick)
        path  = File.expand_path(path.to_s)
        files = ruby_files(path)

        by_file = {}
        by_rule = {}
        total   = 0
        autofix = 0

        files.each do |file|
          code = File.read(file)
          findings = collect(code, file, depth: depth)
          next if findings.empty?

          by_file[file] = findings
          findings.each do |finding|
            rule_key = finding[:rule] || :unknown
            (by_rule[rule_key] ||= []) << finding.merge(file: file)
            total   += 1
            autofix += 1 if finding[:autofix]
          end
        rescue StandardError
          next
        end

        { files: files.size, scanned: by_file.size, total: total,
          autofix_eligible: autofix, by_rule: by_rule, by_file: by_file }
      end

      # Apply all rules that respond to .fix(content) to every source file under path.
      # Returns { fixed: N, errors: [] }.
      def fix_all!(path = MASTER.root)
        path  = File.expand_path(path.to_s)
        rules = fixable_rules
        return { fixed: 0, errors: [] } if rules.empty?

        exts  = %w[.rb .yml .yaml .md .sh .txt .erb .conf .gemspec .js .ts .css .svg .json]
        files = Dir.glob(File.join(path, "**", "*")).select do |f|
          File.file?(f) && exts.include?(File.extname(f)) &&
            !f.match?(%r{/(vendor|var/bundle|\.git|node_modules)/})
        end

        fixed  = 0
        errors = []

        files.each do |file|
          orig = File.binread(file)
          content = orig.dup.force_encoding("utf-8")
          content = content.encode("utf-8", invalid: :replace, undef: :replace)
          rules.each { |rule| content = rule.fix(content) }
          next if content.b == orig.b

          File.binwrite(file, content)
          fixed += 1
        rescue StandardError => e
          errors << "#{file}: #{e.message}"
        end

        { fixed: fixed, errors: errors }
      end

      private

      def fixable_rules
        loaded_plugin_rules.select { |r| r.respond_to?(:fix) }
      end

      def ruby_files(path)
        if File.file?(path)
          [path]
        else
          Dir.glob(File.join(path, "**", "*.rb")).reject { |f| f.include?("/vendor/") || f.include?("/tmp/") }
        end
      end

      def collect(code, file, depth:)
        findings = []

        # :quick -- fast literal pattern check, no LLM (always runs)
        if defined?(CodeReview::Violations)
          literals = CodeReview::Violations.check_literal(code)
          findings.concat(literals.map { |v| normalise(v, rule: :literal) })
        end

        return findings if depth == :quick

        # :standard -- structural smells via CodeReview::Engine
        if %i[standard deep].include?(depth)
          if defined?(CodeReview::Engine)
            engine_result = CodeReview::Engine.analyze_all(code, path: file)
            if engine_result.ok?
              (engine_result.value[:smells] || []).each do |smell|
                findings << normalise(smell, rule: :smell)
              end
            end
          end
        end

        # :hunt -- 8-phase bug analysis via BugHunting
        if %i[hunt deep].include?(depth)
          if defined?(BugHunting)
            hunt_result = BugHunting.analyze(code, file_path: file)
            (hunt_result[:bugs] || hunt_result[:issues] || []).each do |bug|
              findings << normalise(bug, rule: :bug)
            end
          end
        end

        # :critique -- constitutional validation via Violations
        if %i[critique deep].include?(depth)
          if defined?(Violations)
            violations = Violations.analyze(code, path: file, llm: nil, conceptual: false)
            (violations || []).each do |v|
              findings << normalise(v, rule: :constitution)
            end
          end
        end

        return findings unless depth == :deep

        # :deep -- constitutional enforcer (LLM-optional)
        if defined?(Review::Enforcer)
          enforcer_result = Review::Enforcer.check(code, filename: file)
          (enforcer_result[:violations] || []).each do |v|
            findings << normalise(v, rule: :enforcer)
          end
        end

        # :deep -- Scan::Rule plugins loaded from lib/scan/rules/
        loaded_plugin_rules.each do |rule_mod|
          rule_mod.check(code, path: file).each do |finding|
            findings << normalise(finding, rule: finding[:rule] || :scanner_check)
          end
        end

        findings
      end

      # Normalise findings from different systems into a shared shape
      def normalise(finding, rule:)
        {
          rule:      rule,
          name:      finding[:name]    || finding[:check]       || rule,
          message:   finding[:message] || finding[:description] || finding.to_s,
          line:      finding[:line]    || finding[:lineno]      || 0,
          severity:  finding[:severity] || :info,
          autofix:   finding.fetch(:autofix, false),
          principle: finding[:principle],
        }
      end

      # Require lib/scan/rules/*.rb once and return all modules that respond to .check.
      def loaded_plugin_rules
        @loaded_plugin_rules ||= begin
          rules_glob = File.join(__dir__, "scan", "rules", "*.rb")
          Dir.glob(rules_glob).sort.each { |rule_file| require rule_file }
          MASTER::Scan::Rules.constants
                             .map    { |const_name| MASTER::Scan::Rules.const_get(const_name) }
                             .select { |mod| mod.respond_to?(:check) }
        end
      end
    end
  end
end
