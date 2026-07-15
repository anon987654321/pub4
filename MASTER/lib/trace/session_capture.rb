# frozen_string_literal: true

require "fileutils"
require "time"
require "yaml"

module Master
  module Trace
    class SessionCapture
      QUESTIONS = {
        techniques: "What new techniques did the session uncover?",
        recurring_patterns: "What patterns kept recurring?",
        automations: "What manual steps merit automation?",
        prompts: "What questions yielded good results?",
        providers: "What external tools/APIs were useful?",
        learned_behavior: "What made this work?",
      }.freeze

      def initialize(root:)
        @root = root
      end

      def call(text)
        capture = parse(text)
        write_session_learning(capture)
        update_patterns(capture)
        update_openbsd(capture)
        update_soul(capture)
        "capture: recorded #{capture[:summary]}"
      end

      private

      def parse(text)
        raw = text.to_s.strip
        values = extract_fields(raw)
        values[:summary] ||= raw.sub(/\s+\w+=.*/m, "").strip
        values[:summary] = "session outcome" if values[:summary].empty?
        QUESTIONS.each { |key, question| values[key] ||= question }
        values[:timestamp] = Time.now.utc.iso8601
        values
      end

      def extract_fields(raw)
        keys = QUESTIONS.keys.map(&:to_s).join("|")
        raw.scan(/\b(#{keys})=([\s\S]*?)(?=\s+(?:#{keys})=|\z)/).each_with_object({}) do |(key, value), memo|
          memo[normalize_key(key)] = value.strip
        end
      end

      def normalize_key(key)
        key.to_s.downcase.gsub(/[^a-z0-9]+/, "_").sub(/\A_+/, "").sub(/_+\z/, "").to_sym
      end

      def write_session_learning(capture)
        path = File.join(@root, "runtime", "session_learnings.md")
        FileUtils.mkdir_p(File.dirname(path))
        File.open(path, "a") do |file|
          file.puts "## #{capture[:timestamp]} #{capture[:summary]}"
          QUESTIONS.each_value { |question| file.puts "- #{question}" }
          file.puts "- Techniques: #{capture[:techniques]}"
          file.puts "- Recurring patterns: #{capture[:recurring_patterns]}"
          file.puts "- Automation candidates: #{capture[:automations]}"
          file.puts
        end
      end

      def update_patterns(capture)
        path = File.join(@root, "data", "patterns.yml")
        data = read_yaml(path)
        session = data["session_capture"] ||= {}
        prompts = session["high_yield_prompts"] ||= []
        append_unique(prompts, capture[:prompts])
        write_yaml(path, data)
      end

      def update_openbsd(capture)
        return unless capture[:providers].to_s.match?(/openbsd|rcctl|relayd|httpd|pf|doas|pkg_add/i)

        path = File.join(@root, "data", "openbsd.yml")
        data = read_yaml(path)
        providers = data["providers"] ||= []
        append_unique(providers, capture[:providers])
        write_yaml(path, data)
      end

      def update_soul(capture)
        path = File.join(@root, "data", "soul.yml")
        data = read_yaml(path)
        behaviors = data["learned_behaviors"] ||= []
        append_unique(behaviors, capture[:learned_behavior])
        write_yaml(path, data)
      end

      def append_unique(list, value)
        item = value.to_s.strip
        return if item.empty? || list.include?(item)

        list << item
      end

      def read_yaml(path)
        return {} unless File.exist?(path)

        Master.load_yaml(path) || {}
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "SessionCapture.read_yaml")
        {}
      end

      def write_yaml(path, data)
        File.write(path, data.to_yaml)
      end
    end
  end
end
