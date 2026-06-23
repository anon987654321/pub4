# frozen_string_literal: true

module Master
  module Judge
    module Scan
      require_relative "finding"

      class Rule
        EXT_LANG = {
          ".rb" => "ruby", ".rake" => "ruby", ".gemspec" => "ruby",
          ".erb" => "html", ".html" => "html", ".htm" => "html",
          ".css" => "css", ".scss" => "scss", ".sass" => "scss",
          ".js" => "javascript", ".ts" => "javascript",
          ".jsx" => "javascript", ".tsx" => "javascript",
          ".zsh" => "zsh", ".sh" => "zsh", ".bash" => "zsh",
          ".yml" => "yaml", ".yaml" => "yaml",
          ".md" => "markdown", ".json" => "json",
        }.freeze

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

        def check(code, path:)
          raise NotImplementedError, "#{self.class}#check not implemented"
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
            message: message,
            line: line,
            severity: @severity,
            fix: fix,
            tags: @rule_tags,
            confidence: confidence || default_confidence,
            why: why || default_why(message),
            genealogy: genealogy || default_genealogy(message),
            dedupe_key: dedupe_key || default_dedupe_key(message),
            impact_radius: impact_radius
          )
        end

        def scan_lines(code, pattern, message:, fix: nil)
          code.each_line.with_index(1).filter_map { |line, num|
            finding(line: num, message: message, fix: fix) if line.match?(pattern)
          }
        end

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
