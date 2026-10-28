# frozen_string_literal: true

require "json"
require "ripper"
require "set"

module Operator

  # What a reading copy of a file loses, format by format.
  #
  # Comments and blank lines come out and nothing else does. A line inside a string or heredoc is
  # left exactly as written, the first comment before any code stays as a one-line purpose, and
  # Ruby that no longer parses is returned as it was.
  module SnapshotMinify
    PURPOSE_WIDTH = 110
    NAMED_RUBY = %w[Gemfile Rakefile Guardfile Capfile Brewfile Vagrantfile config.ru].freeze
    PRAGMA = /\A#\s*(frozen_string_literal|encoding|coding|typed|rubocop|-\*-)/i
    DECORATION = /\A[-=_*#]+\z/

    HANDLERS = {
      ".rb" => :ruby, ".rake" => :ruby, ".gemspec" => :ruby, ".ru" => :ruby,
      ".js" => :javascript, ".mjs" => :javascript, ".jsx" => :javascript, ".ts" => :javascript, ".tsx" => :javascript,
      ".css" => :stylesheet, ".scss" => :stylesheet,
      ".yml" => :yaml, ".yaml" => :yaml, ".json" => :json,
      ".erb" => :markup, ".html" => :markup, ".md" => :markdown,
      ".sh" => :hash_commented, ".zsh" => :hash_commented, ".ksh" => :hash_commented,
      ".conf" => :hash_commented, ".zone" => :hash_commented
    }.freeze

    RubyScan = Struct.new(:comments, :strings, :first_code)

    module_function

    def call(path, text)
      text = text.to_s.dup.force_encoding(Encoding::UTF_8).scrub
      extension = File.extname(path).downcase
      return extensionless(path, text) if extension.empty?

      method(HANDLERS.fetch(extension, :squeeze)).call(text)
    end

    def extensionless(path, text)
      ruby_script = NAMED_RUBY.include?(File.basename(path)) || text.lines.first.to_s.match?(/\A#!.*ruby/)

      ruby_script ? ruby(text) : hash_commented(text)
    end

    def ruby(text)
      return squeeze(text) if text.empty? || Ripper.sexp(text).nil?

      tokens = Ripper.lex(text)
      scan = ruby_scan(tokens)
      body = text.lines.each_with_index.filter_map { |raw, index| ruby_line(raw, number: index + 1, scan:) }
      purpose = ruby_purpose(tokens, scan.first_code)
      body.insert(purpose_index(body), purpose) if purpose
      result = "#{body.join("\n")}\n"

      Ripper.sexp(result) ? result : text
    rescue StandardError
      squeeze(text)
    end

    def ruby_scan(tokens)
      comments = {}
      strings = Set.new
      first_code = nil

      tokens.each do |(line, col), type, tok, _state|
        case type
        when :on_comment then comments[line] = col
        when :on_embdoc_beg, :on_embdoc, :on_embdoc_end then comments[line] = 0
        when :on_sp, :on_nl, :on_ignored_nl then next
        else
          first_code ||= line
          strings.merge(line..(line + tok.count("\n"))) if type == :on_tstring_content
        end
      end

      RubyScan.new(comments, strings, first_code)
    end

    # nil drops the line. A line inside a string keeps its trailing whitespace: it is the string.
    def ruby_line(raw, number:, scan:)
      return raw.rstrip if number == 1 && raw.start_with?("#!")

      if (col = scan.comments[number])
        kept = raw[0, col].to_s.rstrip
        return kept.empty? ? nil : kept
      end

      inside = scan.strings.include?(number)
      return if raw.strip.empty? && !inside

      inside ? raw.chomp : raw.rstrip
    end

    def ruby_purpose(tokens, first_code)
      tokens.each do |(line, _col), type, tok, _state|
        break if first_code && line >= first_code
        next unless type == :on_comment
        next if tok.match?(PRAGMA) || tok.start_with?("#!")

        purpose = comment_purpose(tok)
        return purpose if purpose
      end

      nil
    end

    def comment_purpose(comment)
      body = comment.strip.sub(/\A#+\s?/, "").strip
      return if body.empty? || body.match?(DECORATION) || body.start_with?("---")

      "# #{body[0, PURPOSE_WIDTH]}"
    end

    def purpose_index(body) = body.first.to_s.start_with?("#!") ? 1 : 0

    # Whole-line comments only: a "//" inside a string or a regexp is not touched.
    def javascript(text)
      body = []
      in_block = false

      text.each_line do |raw|
        stripped = raw.strip
        in_block, part_of_block = js_block_state(stripped, in_block)
        next if part_of_block || stripped.empty? || js_line_comment?(stripped)

        body << raw.rstrip
      end

      "#{body.join("\n")}\n"
    end

    # [still inside a block comment after this line, this line belongs to one]
    def js_block_state(stripped, in_block)
      opens = stripped.start_with?("/*") && !stripped.start_with?("/*!")
      return [!stripped.include?("*/"), true] if in_block || opens

      [false, false]
    end

    def js_line_comment?(stripped) = stripped.start_with?("//") && !stripped.start_with?("//#")

    def stylesheet(text)
      lines = text.gsub(%r{/\*.*?\*/}m, "").lines.map(&:strip)

      "#{lines.reject { |line| line.empty? || line.start_with?("//") }.join("\n")}\n"
    end

    def yaml(text)
      body = []

      text.each_line do |raw|
        stripped = raw.strip
        next if stripped.empty?
        next body << raw.rstrip unless stripped.start_with?("#")

        purpose = body.empty? ? comment_purpose(stripped) : nil
        body << purpose if purpose
      end

      "#{body.join("\n")}\n"
    end

    def json(text)
      "#{JSON.generate(JSON.parse(text))}\n"
    rescue JSON::ParserError
      squeeze(text)
    end

    def markup(text)
      kept = text.lines.map(&:strip).reject do |line|
        line.empty? || line.match?(/\A<%#.*%>\z/) || line.match?(/\A<!--.*-->\z/)
      end

      "#{kept.join("\n")}\n"
    end

    def markdown(text) = "#{text.gsub(/[ \t]+$/, '').gsub(/\n{3,}/, "\n\n").strip}\n"

    # Shell, configuration and zone files: whole-line comments come out, and the first one before
    # any code stays as the file's one-line purpose, as it does for Ruby.
    def hash_commented(text)
      body = []
      purpose = nil

      text.each_line.with_index do |raw, index|
        stripped = raw.strip
        next if stripped.empty?
        next body << raw.rstrip unless stripped.start_with?("#")

        if index.zero? && stripped.start_with?("#!")
          body << raw.rstrip
        elsif purpose.nil? && body.all? { |line| line.start_with?("#!") }
          purpose = comment_purpose(stripped)
        end
      end

      body.insert(purpose_index(body), purpose) if purpose
      "#{body.join("\n")}\n"
    end

    def squeeze(text) = "#{text.lines.map(&:rstrip).reject(&:empty?).join("\n")}\n"
  end
end
