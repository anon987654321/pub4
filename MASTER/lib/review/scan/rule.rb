# frozen_string_literal: true

module Master
  module Review
    module Scan
      require_relative "finding"

      class Rule
        include SourceMasking

        EXT_LANG = Master::FILE_LANGUAGE_MAP

        attr_reader :id, :description, :severity, :rule_tags, :auto_fix

        @registry = []
        @registry_mutex = Mutex.new

        def self.inherited(subclass)
          @registry_mutex.synchronize { @registry << subclass }
        end

        def self.registry
          @registry_mutex.synchronize { @registry.dup }
        end

        # Rules that need constructor args (root:, agent:) override this to false.
        # Builder uses it to auto-discover zero-arg rules from the registry.
        def self.auto_build?
          true
        end

        def initialize
          @id = self.class.name&.split("::")&.last&.downcase || "unknown"
          @description = ""
          @severity = :warning
          @rule_tags = []
          @auto_fix = true
        end

        # Default for AST-based rules: a subclass implements check_ast and gets
        # this for free. Rules with non-AST logic override #check instead.
        def check(code, path:)
          raise NotImplementedError, "#{self.class}#check not implemented" unless respond_to?(:check_ast)

          return [] unless path.to_s.end_with?(".rb", ".rake")

          check_ast(Prism.parse(code).value, code, path:)
        rescue StandardError => e
          # [] is also a clean file's answer, so only this report separates them.
          Master::Ground::Swallow.log(e, context: "#{self.class}#check_ast", severity: :load_bearing, path:)
          []
        end

        def language(path)
          return "javascript" if File.basename(path).match?(/\Aface\.part\d+\.txt\z/)
          EXT_LANG[File.extname(path).downcase]
        end

        def applies_to?(path, languages)
          return true if languages.nil? || languages.empty?
          lang = language(path)
          lang && languages.include?(lang)
        end

        protected

        def finding(line:, message:, fix: nil, confidence: nil, why: nil, genealogy: nil, impact_radius: nil, dedupe_key: nil)
          Finding.build(
            rule: @id,
            message:,
            line:,
            severity: @severity,
            fix:,
            tags: @rule_tags,
            confidence: confidence || default_confidence,
            why: why || default_why(message),
            genealogy: genealogy || default_genealogy(message),
            dedupe_key: dedupe_key || default_dedupe_key(message),
            impact_radius:,
          )
        end

        def scan_lines(code, pattern, message:, fix: nil)
          code.each_line.with_index(1).filter_map do |line, num|
            # The law engine honours the same marker: a line that declares
            # itself intentional carries a reviewer's reason beside it.
            next if line.match?(/scan:\s*intentional\b/)
            finding(line: num, message:, fix:) if line.match?(pattern)
          end
        end

        # A raw regex over raw lines makes a comment that names the thing the rule
        # forbids into a finding about itself. BARE_RESCUE and FAIL_VISIBLY both
        # fired on the paragraph in lexical_rules.rb explaining which rescue shape
        # each rule owns; veto unsafe_calls fires on a comment describing a shell
        # interpolation. Blanked to spaces, so line numbers still line up.
        #

        def default_confidence
          case @severity
          when :error then 0.9
          when :warning then 0.78
          else 0.62
          end
        end

        def default_why(message)
          "#{message} because it tends to increase maintenance risk and regression cost."
        end

        def default_genealogy(message)
          [@rule_tags.first || "GENERAL", @id, message.to_s.split(" — ").first.to_s]
        end

        def default_dedupe_key(message)
          "#{@id}:#{message.to_s.downcase.gsub(/\b\d+\b/, "#")}"
        end
      end
    end
  end
end
