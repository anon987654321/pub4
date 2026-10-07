# frozen_string_literal: true

require "ripper"
require "set"
require "json"
require_relative "../lib/trace/dmesg"

module Operator
  module EventBusReach
    REPO = File.expand_path("../..", __dir__)
    MASTER = File.join(REPO, "MASTER")

    RUBY_GLOBS = %w[
      lib/**/*.rb
      core/**/*.rb
      web/app/**/*.rb
      web/config/**/*.rb
      bin/*
      tools/**/*.rb
      test/**/*.rb
      law/*.rb
      Rakefile
    ].freeze

    JS_GLOBS = %w[
      web/public/**/*.js
      web/public/**/*.mjs
      web/app/**/*.js
    ].freeze

    PUBLISH_METHODS = %w[publish].freeze
    SUBSCRIBE_METHODS = %w[subscribe].freeze
    EVENT_NAME = /\A[a-z][a-z0-9_]*:[a-z][a-z0-9_:-]*\z/
    WILDCARDS = ["*", "**"].freeze

    module_function

    def files(globs)
      Dir.glob(globs.flat_map { |glob| File.join(MASTER, glob) })
         .select { |path| File.file?(path) }
         .reject { |path| File.basename(path).end_with?(".bundle.js") }
         .sort
    end

    def ruby_files = @ruby_files ||= files(RUBY_GLOBS)
    def js_files = @js_files ||= files(JS_GLOBS)

    def read(path)
      File.read(path, encoding: "UTF-8")
    end

    def ruby_events(source)
      sexp = Ripper.sexp(source)
      return [] unless sexp

      events = []
      walk(sexp) do |node|
        next unless node.is_a?(Array) && node[0] == :method_add_arg

        call = node[1]
        method = call_method_name(call)
        next unless PUBLISH_METHODS.include?(method) || SUBSCRIBE_METHODS.include?(method)

        topic = first_string_argument(node[2])
        next unless topic

        role = PUBLISH_METHODS.include?(method) ? :publisher : :subscriber
        events << { topic:, role: }
      end
      events
    end

    def call_method_name(node)
      return unless node.is_a?(Array)

      case node[0]
      when :call
        node[3].is_a?(Array) ? node[3][1].to_s : nil
      when :fcall
        node[1].is_a?(Array) ? node[1][1].to_s : nil
      end
    end

    def first_string_argument(arg_paren)
      return unless arg_paren.is_a?(Array) && arg_paren[0] == :arg_paren

      args = arg_paren[1]
      return unless args.is_a?(Array) && args[0] == :args_add_block

      value = args[1]&.first
      return unless value.is_a?(Array) && value[0] == :string_literal

      body = value[1]
      return unless body.is_a?(Array) && body[0] == :string_content

      parts = body.drop(1)
      return unless parts.all? { |part| part.is_a?(Array) && part[0] == :@tstring_content }

      parts.map { |part| part[1] }.join
    end

    def js_events(source)
      code = strip_comments(source)
      rows = []

      code.to_enum(:scan, /\b(?:window\.)?(?:addEventListener|subscribe)\s*\(\s*(['"])([^'"]+)\1/).each do
        match = Regexp.last_match
        topic = match[2]
        rows << { topic:, role: :listener } if event_topic?(topic)
      end

      code.to_enum(:scan, /\b(?:emitTtsEvent|dispatchEvent)\s*\(\s*(?:new\s+CustomEvent\s*\(\s*)?(['"])([^'"]+)\1/).each do
        match = Regexp.last_match
        topic = match[2]
        rows << { topic:, role: :publisher } if event_topic?(topic)
      end

      rows.concat(js_references(code))
      rows
    end

    def js_references(source)
      source.scan(%r{/((?:\\.|[^/\\\n])*)/[a-z]*}i).flat_map do |body|
        body = body.to_s
        topics = body.scan(/[a-z][a-z0-9_]*:[a-z][a-z0-9_:-]*/)
        topics.concat(expanded_regex_topics(body))
        topics.uniq.filter_map do |topic|
          { topic:, role: :reference } if event_topic?(topic)
        end
      end
    end

    def expanded_regex_topics(body)
      text = body.to_s
      topics = []

      # Non-capturing and capturing groups: prefix:(?:a|b) / prefix:(a|b).
      text.scan(/([a-z][a-z0-9_]*):\((?:\?:)?([a-z][a-z0-9_:-]*(?:\|[a-z][a-z0-9_:-]*)+)\)/) do |prefix, alternatives|
        alternatives.split("|").each { |suffix| topics << "#{prefix}:#{suffix}" }
      end

      # Bare alternation with a repeated topic prefix:
      # prefix:a|prefix:b|prefix:c. Keep the prefix on every arm so ordinary
      # regex alternation cannot manufacture unrelated event topics.
      text.scan(/(([a-z][a-z0-9_]*):[a-z][a-z0-9_:-]*(?:\|\2:[a-z][a-z0-9_:-]*)+)/) do |match|
        match = match.first
        prefix = match[/\A[a-z][a-z0-9_]*/]
        match.scan(/#{Regexp.escape(prefix)}:([a-z][a-z0-9_:-]*)/).flatten.each do |suffix|
          topics << "#{prefix}:#{suffix}"
        end
      end

      topics.uniq
    end

    def strip_comments(source)
      out = +""
      state = :code
      escape = false
      i = 0

      while i < source.length
        char = source[i]
        nxt = source[i + 1]

        case state
        when :code
          if char == "/" && nxt == "/"
            out << "  "
            state = :line_comment
            i += 2
            next
          elsif char == "/" && nxt == "*"
            out << "  "
            state = :block_comment
            i += 2
            next
          elsif char == "'"
            state = :single
          elsif char == '"'
            state = :double
          elsif char == "`"
            state = :template
          end
          out << char
        when :single, :double, :template
          out << char
          if escape
            escape = false
          elsif char == "\\"
            escape = true
          elsif (state == :single && char == "'") ||
                (state == :double && char == '"') ||
                (state == :template && char == "`")
            state = :code
          end
        when :line_comment
          if char == "\n"
            out << "\n"
            state = :code
          else
            out << " "
          end
        when :block_comment
          if char == "*" && nxt == "/"
            out << "  "
            state = :code
            i += 2
            next
          end
          out << (char == "\n" ? "\n" : " ")
        end

        i += 1
      end

      out
    end

    def event_topic?(topic)
      value = topic.to_s
      EVENT_NAME.match?(value) && !WILDCARDS.include?(value)
    end

    def walk(node, &)
      yield node
      return unless node.is_a?(Array)

      node.each { |child| walk(child, &) if child.is_a?(Array) }
    end

    def relative(path)
      path.delete_prefix("#{MASTER}/")
    end

    def collect
      publishers = Hash.new { |h, k| h[k] = [] }
      subscribers = Hash.new { |h, k| h[k] = [] }
      listeners = Hash.new { |h, k| h[k] = [] }
      references = Hash.new { |h, k| h[k] = [] }

      ruby_files.each do |path|
        ruby_events(read(path)).each do |event|
          bucket = event[:role] == :publisher ? publishers : subscribers
          bucket[event[:topic]] << relative(path)
        end
      end

      js_files.each do |path|
        js_events(read(path)).each do |event|
          case event[:role]
          when :publisher then publishers[event[:topic]] << relative(path)
          when :listener then listeners[event[:topic]] << relative(path)
          when :reference then references[event[:topic]] << relative(path)
          end
        end
      end

      {
        publishers: collapse(publishers),
        subscribers: collapse(subscribers),
        listeners: collapse(listeners),
        references: collapse(references),
      }
    end

    def collapse(rows)
      rows.transform_values { |paths| paths.uniq.sort }
    end

    def report
      data = collect
      topics = (data.values.flat_map(&:keys)).to_set
      published = data[:publishers].keys.to_set
      consumed = (data[:subscribers].keys + data[:listeners].keys).to_set

      unpublished = topics.select { |topic| !published.include?(topic) }.sort
      unconsumed = published.reject { |topic| consumed.include?(topic) }.sort

      {
        **data,
        unpublished: unpublished,
        unconsumed: unconsumed,
      }
    end

    def print_report(io: $stdout, strict: false, json: false)
      result = report

      if json
        io.puts(JSON.pretty_generate(result))
        return strict && (result[:unpublished].any? || result[:unconsumed].any?) ? 1 : 0
      end

      Master::Trace::Dmesg.attach(
        "eventbus0", "master0",
        "#{result[:publishers].size} publishers, #{result[:subscribers].size} Ruby subscribers, #{result[:listeners].size} browser listeners, #{result[:references].size} browser references",
        io:
      )

      unless result[:unpublished].empty?
        Master::Trace::Dmesg.status("eventbus0", "topics with no publisher", io:)
        result[:unpublished].each do |topic|
          roles = []
          roles << "ruby subscribers #{result[:subscribers][topic].join(", ")}" if result[:subscribers].key?(topic)
          roles << "browser listeners #{result[:listeners][topic].join(", ")}" if result[:listeners].key?(topic)
          roles << "browser references #{result[:references][topic].join(", ")}" if result[:references].key?(topic)
          Master::Trace::Dmesg.status("eventbus0", "#{topic}, #{roles.join("; ")}", io:)
        end
      end

      unless result[:unconsumed].empty?
        Master::Trace::Dmesg.status("eventbus0", "published topics with no subscriber or listener", io:)
        result[:unconsumed].each do |topic|
          Master::Trace::Dmesg.status("eventbus0", "#{topic}, publishers #{result[:publishers][topic].join(", ")}", io:)
        end
      end

      strict && (result[:unpublished].any? || result[:unconsumed].any?) ? 1 : 0
    end
  end
end

if $PROGRAM_NAME == __FILE__
  exit Operator::EventBusReach.print_report(strict: ARGV.include?("--strict"), json: ARGV.include?("--json"))
end
