# frozen_string_literal: true

module MASTER
  # Scan — single traversal, pluggable rule modules.
  # Replaces three separate Dir.glob loops in code_review/, review/, analysis/.
  #
  # Usage:
  #   Scan.run("lib/")                    # :quick — literal patterns only, no LLM
  #   Scan.run("lib/", depth: :standard)  # + structural smells (CodeReview::Engine)
  #   Scan.run("lib/", depth: :deep)      # + constitutional enforcer (Review::Enforcer)
  #
  # Returns: { files: N, total: N, autofix_eligible: N, by_rule: { rule_name => [findings] }, by_file: { path => [findings] } }
  module Scan
    DEPTHS = %i[quick standard deep].freeze

    # A Rule is anything that responds to .check(code, path:) → Array<Hash>
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

      private

      def ruby_files(path)
        if File.file?(path)
          [path]
        else
          Dir.glob(File.join(path, "**", "*.rb")).reject { |f| f.include?("/vendor/") || f.include?("/tmp/") }
        end
      end

      def collect(code, file, depth:)
        findings = []

        # :quick — fast literal pattern check, no LLM (always runs)
        if defined?(CodeReview::Violations)
          literals = CodeReview::Violations.check_literal(code)
          findings.concat(literals.map { |v| normalise(v, rule: :literal) })
        end

        return findings if depth == :quick

        # :standard — structural smells via CodeReview::Engine
        if depth == :standard || depth == :deep
          if defined?(CodeReview::Engine)
            engine_result = CodeReview::Engine.analyze_all(code, path: file)
            if engine_result.ok?
              (engine_result.value[:smells] || []).each do |smell|
                findings << normalise(smell, rule: :smell)
              end
            end
          end
        end

        return findings unless depth == :deep

        # :deep — constitutional enforcer (LLM-optional)
        if defined?(Review::Enforcer)
          enforcer_result = Review::Enforcer.check(code, filename: file)
          (enforcer_result[:violations] || []).each do |v|
            findings << normalise(v, rule: :constitution)
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
    end
  end
end
