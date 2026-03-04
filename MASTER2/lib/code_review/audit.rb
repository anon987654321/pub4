# frozen_string_literal: true

module CodeReview
  class Audit
    DEFAULT_MAX_FILE_LINES = 300
    DEFAULT_MAX_METHOD_LINES = 20
    MAX_SCAN_RESULTS = 10_000

    RUBY_EXTENSIONS = [".rb", ".rake", ".gemspec"].freeze
    SNAKE_CASE = /\A[a-z][a-z0-9_]*\z/.freeze
    CAMEL_CASE = /\A[A-Z][A-Za-z0-9]*\z/.freeze

    Offense = Struct.new(:file, :line, :message, keyword_init: true)

    def scan(root, max_file_lines: DEFAULT_MAX_FILE_LINES, max_method_lines: DEFAULT_MAX_METHOD_LINES)
      root = root.to_s.strip
      return [] if root.empty?

      files = ruby_files_under(root)
      return [] if files.empty?

      offenses = files.flat_map do |file|
        check_file(file, max_file_lines:, max_method_lines:)
      end

      offenses.first(MAX_SCAN_RESULTS)
    rescue SystemCallError, ArgumentError
      []
    end

    def check_file_length(path, max_lines: DEFAULT_MAX_FILE_LINES)
      return [] unless File.file?(path)

      content = read_file(path)
      return [] if content.nil?

      line_count = content.lines.count
      return [] if line_count <= max_lines

      [
        Offense.new(
          file: path,
          line: 1,
          message: "File too long (#{line_count} lines > #{max_lines})"
        )
      ]
    end

    def check_naming(path)
      base = File.basename(path)
      return [] unless File.file?(path)
      return [] unless ruby_file?(base)

      offenses = []
      offenses.concat(check_file_basename(base, path))
      offenses.concat(check_constant_naming(path))

      offenses
    end

    private

    def check_file(path, max_file_lines:, max_method_lines:)
      [
        check_file_length(path, max_lines: max_file_lines),
        check_naming(path),
        check_method_lengths(path, max_lines: max_method_lines)
      ].flatten
    end

    def ruby_files_under(root)
      return [] unless File.directory?(root)

      Dir.glob(File.join(root, "**", "*")).select do |p|
        File.file?(p) && ruby_file?(p)
      end
    rescue SystemCallError
      []
    end

    def ruby_file?(path)
      ext = File.extname(path)
      RUBY_EXTENSIONS.include?(ext) || File.basename(path) == "Rakefile"
    end

    def read_file(path)
      File.read(path, mode: "r:BOM|UTF-8")
    rescue SystemCallError, ArgumentError
      nil
    end

    def check_file_basename(base, path)
      return [] if base == "Rakefile"

      name = base.sub(/\.[^.]+\z/, "")
      return [] if name.match?(SNAKE_CASE)

      [
        Offense.new(
          file: path,
          line: 1,
          message: "File name should be snake_case: #{base}"
        )
      ]
    end

    def check_constant_naming(path)
      content = read_file(path)
      return [] if content.nil?

      offenses = []
      content.each_line.with_index(1) do |line, lineno|
        const_name = extract_constant_name(line)
        next if const_name.nil? || const_name.match?(CAMEL_CASE)

        offenses << Offense.new(
          file: path,
          line: lineno,
          message: "Constant should be CamelCase: #{const_name}"
        )
      end
      offenses
    end

    def extract_constant_name(line)
      match = line.match(/^\s*([A-Z][A-Za-z0-9_]*)\s*=\s*/)
      match && match[1]
    end

    def check_method_lengths(path, max_lines:)
      content = read_file(path)
      return [] if content.nil?

      methods = extract_ruby_methods(content)
      methods.flat_map do |m|
        next [] if m[:lines] <= max_lines

        [
          Offense.new(
            file: path,
            line: m[:start_line],
            message: "Method '#{m[:name]}' is #{m[:lines]} lines (>#{max_lines})"
          )
        ]
      end
    end

    def extract_ruby_methods(content)
      methods = []
      stack = []
      lineno = 0

      content.each_line do |line|
        lineno += 1
        if (name = parse_method_definition(line))
          stack << { name:, start_line: lineno, depth: 0 }
          next
        end

        next if stack.empty?

        stack[-1][:depth] += 1 if opens_block?(line)
        stack[-1][:depth] -= 1 if closes_block?(line)

        if ends_method?(line, stack[-1][:depth])
          m = stack.pop
          methods << { name: m[:name], start_line: m[:start_line], lines: lineno - m[:start_line] + 1 }
        end
      end

      methods
    end

    def parse_method_definition(line)
      match = line.match(/^\s*def\s+(self\.)?([a-zA-Z_][a-zA-Z0-9_!?=]*)/)
      match && match[2]
    end

    def opens_block?(line)
      line.match?(/\b(do|class|module|def|if|unless|case|while|until|for|begin)\b/) && !line.strip.start_with?("#")
    end

    def closes_block?(line)
      line.match?(/^\s*end\b/)
    end

    def ends_method?(line, depth)
      line.match?(/^\s*end\b/) && depth <= 0
    end
  end
end