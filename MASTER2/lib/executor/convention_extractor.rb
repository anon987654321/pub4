# frozen_string_literal: true

require 'json'

module Executor
  class ConventionExtractor
    DEFAULT_INDENT = '  '
    OUTPUT_MARGIN = '      '
    LINES_PUSH_PREFIX = "#{OUTPUT_MARGIN}lines << ".freeze

    ASSOCIATIONS_TO_PRELOAD = %i[project author rules].freeze

    MAX_NAME_LENGTH = 80
    DEFAULT_VERSION = 1

    def initialize(scope: nil, indent: DEFAULT_INDENT)
      @scope = scope
      @indent = indent
    end

    def call
      conventions = load_conventions
      return '' if conventions.empty?

      lines = []
      build_header(lines)
      build_conventions(lines, conventions)
      build_footer(lines)
      lines.join("\n")
    end

    private

    attr_reader :scope, :indent

    def load_conventions
      relation = scope || Convention.all
      relation.includes(*ASSOCIATIONS_TO_PRELOAD).order(:id).to_a
    end

    def build_header(lines)
      lines << '# frozen_string_literal: true'
      lines << ''
      lines << 'module ConventionRegistry'
      lines << "#{indent}def self.load"
      lines << "#{indent}#{indent}lines = []"
    end

    def build_footer(lines)
      lines << "#{indent}#{indent}lines"
      lines << "#{indent}end"
      lines << 'end'
    end

    def build_conventions(lines, conventions)
      conventions.each do |convention|
        build_convention(lines, convention)
      end
    end

    def build_convention(lines, convention)
      name = safe_name(convention.name)
      return if name.nil?

      push_line(lines, %(# Convention: #{name}))
      push_line(lines, %(lines << "#{escape(name)}"))

      project_name = convention.project&.name
      push_line(lines, %(lines << "project: #{escape(project_name)}")) if project_name

      author_name = convention.author&.name
      push_line(lines, %(lines << "author: #{escape(author_name)}")) if author_name

      version = convention.respond_to?(:version) ? convention.version : nil
      version ||= DEFAULT_VERSION
      push_line(lines, %(lines << "version: #{version}"))

      rules = convention.respond_to?(:rules) ? Array(convention.rules) : []
      build_rules(lines, rules)

      push_line(lines, %(lines << "")) # separator
    end

    def build_rules(lines, rules)
      return if rules.empty?

      push_line(lines, %(lines << "rules:"))
      rules.each do |rule|
        push_rule(lines, rule)
      end
    end

    def push_rule(lines, rule)
      text = rule.respond_to?(:text) ? rule.text : rule.to_s
      return if text.nil? || text.strip.empty?

      push_line(lines, %(lines << "- #{escape(text)}"))
    end

    def safe_name(name)
      return nil if name.nil?

      str = name.to_s.strip
      return nil if str.empty?

      str.length > MAX_NAME_LENGTH ? str[0, MAX_NAME_LENGTH] : str
    end

    def escape(value)
      value.to_s.gsub('\\', '\\\\').gsub('"', '\"')
    end

    def push_line(lines, content)
      lines << "#{LINES_PUSH_PREFIX}#{content}"
    end

    def parse_json(json)
      return {} if json.nil? || json.to_s.strip.empty?

      JSON.parse(json)
    rescue JSON::ParserError
      {}
    end
  end
end