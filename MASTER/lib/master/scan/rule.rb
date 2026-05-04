# frozen_string_literal: true

module Master
  module Scan
    class Rule
      EXT_LANG = {
        ".rb"      => "ruby",        ".rake"  => "ruby",   ".gemspec" => "ruby",
        ".erb"     => "html",        ".html"  => "html",   ".htm"     => "html",
        ".css"     => "css",         ".scss"  => "scss",   ".sass"    => "scss",
        ".js"      => "javascript",  ".ts"    => "javascript",
        ".jsx"     => "javascript",  ".tsx"   => "javascript",
        ".zsh"     => "zsh",         ".sh"    => "zsh",    ".bash"    => "zsh",
        ".yml"     => "yaml",        ".yaml"  => "yaml",
        ".md"      => "markdown",    ".json"  => "json",
      }.freeze

      attr_reader :id, :description, :severity, :axiom_tags, :auto_fix

      def self.inherited(subclass)
        @registry_mutex ||= Mutex.new
        @registry_mutex.synchronize do
          (@registry ||= []) << subclass
        end
      end

      def self.registry
        @registry_mutex ||= Mutex.new
        @registry_mutex.synchronize { @registry || [] }
      end

      # Rules that need constructor args (root:, agent:) override this to false.
      # Builder uses it to auto-discover zero-arg rules from the registry.
      def self.auto_build? = true

      def initialize
        @id         = self.class.name&.split("::")&.last&.downcase || "unknown"
        @description = ""
        @severity    = :warning
        @axiom_tags  = []
        @auto_fix    = true
      end

      def check(code, path:)
        raise NotImplementedError, "#{self.class}#check not implemented"
      end

      def language(path)
        EXT_LANG[File.extname(path).downcase]
      end

      def applies_to?(path, languages)
        return true if languages.nil? || languages.empty?
        lang = language(path)
        lang && languages.include?(lang)
      end

      protected

      def finding(line:, message:, fix: nil)
        { rule: @id, message:, line:, severity: @severity, fix: }
      end

      def scan_lines(code, pattern, message:, fix: nil)
        code.each_line.with_index(1).filter_map { |line, num|
          finding(line: num, message:, fix:) if line.match?(pattern)
        }
      end
    end
  end
end
