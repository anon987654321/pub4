# frozen_string_literal: true
module Master
  class Engine
    def initialize(principles:, llm:)
      @principles, @llm = principles, llm
    end

    def scan(path)
      return Result.err("Not found: #{path}") unless File.exist?(path)
      content = File.read(path, encoding: "UTF-8")
      ext = File.extname(path).downcase
      lang = { ".rb" => "ruby", ".py" => "python", ".js" => "javascript",
               ".ts" => "typescript", ".go" => "go", ".rs" => "rust",
               ".sh" => "shell", ".yml" => "yaml", ".yaml" => "yaml" }[ext] || "text"
      lines = content.lines.size
      bytes = content.bytesize
      puts "proc0: #{path} (#{lang}, #{lines} lines, #{bytes} bytes)"
      issues = detect_issues(content, lang)
      Result.ok(issues: issues, path: path, lang: lang)
    end

    private

    def detect_issues(content, lang)
      issues = []
      lines = content.lines
      lines.each_with_index do |line, i|
        issues << { line: i + 1, msg: "Line too long (#{line.size})" } if line.size > 120
        line_trimmed = line.chomp
        issues << { line: i + 1, msg: "Trailing whitespace" } if line_trimmed =~ /[ \t]+$/
        issues << { line: i + 1, msg: "Hard tab" } if line.include?("\t") && lang != "makefile"
      end
      issues << { line: nil, msg: "No final newline" } unless content.end_with?("\n")
      issues << { line: nil, msg: "File too long (#{lines.size} lines)" } if lines.size > 500
      issues
    end
  end
end
