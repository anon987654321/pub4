# frozen_string_literal: true

module MASTER
  module Parser
    module MultiLanguage
      EXTENSIONS = {
        ".rb" => :ruby, ".py" => :python, ".js" => :javascript,
        ".ts" => :typescript, ".sh" => :shell, ".go" => :go,
        ".rs" => :rust, ".c" => :c, ".cpp" => :cpp,
        ".html" => :html, ".css" => :css, ".yml" => :yaml,
        ".yaml" => :yaml, ".json" => :json, ".md" => :markdown,
      }.freeze

      def self.detect_language(path)
        ext = File.extname(path).downcase
        EXTENSIONS[ext] || :unknown
      end

      def self.parse(path)
        return Result.err("File not found: #{path}") unless File.exist?(path)
        content = File.read(path)
        lang = detect_language(path)
        Result.ok(language: lang, content: content, lines: content.lines.size, path: path)
      rescue StandardError => e
        Result.err("Parse error: #{e.message}")
      end
    end
  end
end
