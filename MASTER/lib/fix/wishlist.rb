# frozen_string_literal: true

require "fileutils"
require "time"
require "yaml"
require_relative "../ai/orientation"

module Master
  module Fix
    # Converts the end of a /fix run into a bounded, evidence-linked next-work
    # queue. It proposes; it does not silently edit source. Concrete wishes are
    # surfaced to the next /fix through the orientation layer.
    class Wishlist
      OUT_PATH = "runtime/wishlist.md"
      ITEM_COUNT = 24
      MAX_ITEMS = 40
      MIN_ITEMS = 20

      def initialize(root:, agent:, event_bus: nil)
        @root = root
        @agent = agent
        @bus = event_bus
      end

      def call(state:, target:, run_id:)
        return "wishlist: skipped — no model" unless @agent.respond_to?(:ask)
        orientation = Master::AI::Orientation.render(root: @root, target:, depth: 1, max_entries: 40)
        response = @agent.ask(prompt(orientation:, state:, target:, run_id:))
        items = normalize(parse(response))
        return "wishlist: parse failed" if items.size < MIN_ITEMS

        write_report(items, state:, target:, run_id:)
        @bus&.publish("wishlist:done", drafted: items.size, target:, state:)
        "wishlist: drafted #{items.size} item(s) → #{OUT_PATH}"
      rescue StandardError => e
        @bus&.publish("wishlist:error", error: e.message, state:, target:)
        "wishlist: #{e.class}: #{e.message}"
      end

      def self.pending_context(root, limit: 24)
        path = File.join(root, OUT_PATH)
        return unless File.file?(path)

        lines = File.readlines(path, encoding: "UTF-8", chomp: true)
        sections = lines.slice_before { |line| line.match?(/\A### \d+\./) }.drop(1)
        sections = sections.first(limit)
        sections = sections.select do |section|
          implementation = section.find { |line| line.start_with?("implementation:") }
          implementation.nil? || implementation.match?(/\bnext_fix\b/)
        end
        return if sections.empty?

        body = sections.map(&:join).join("\n")
        <<~TEXT.strip
          Pending wishlist proposals eligible for automatic implementation.
          Treat each supported next_fix proposal as an actual repair target, not as
          a suggestion to discuss. Implement all proposals that remain supported by
          current evidence and constitutional rules. Carry any unimplemented item
          forward by leaving its evidence and anchor intact; never mark operator,
          research, or unsupported external work as completed.
          
          #{body}
        TEXT
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Fix::Wishlist.pending_context")
        nil
      end

      private

      def out_file
        File.join(@root, OUT_PATH)
      end

      def prompt(orientation:, state:, target:, run_id:)
        <<~PROMPT
          You are proposing the next bounded work queue after a completed MASTER /fix run.
          Do not claim a defect unless the supplied evidence supports it.
          Do not repeat work that is already marked done. Prefer concrete improvements
          that a later /fix can implement and verify.

          Run:
          state: #{state}
          target: #{target}
          run_id: #{run_id}

          Orientation:
          #{orientation}

          Produce exactly #{ITEM_COUNT} wishlist items as YAML.
          Each item must contain:
          - id: snake_case
          - title: short human-readable name
          - rationale: one sentence
          - anchor: repository-relative path:line, or run:<state>
          - change: one concrete implementation sentence
          - effort: cheap, medium, or deep
          - reversibility: reversible, guarded, or operator
          - implementation: next_fix, research, or operator
          - evidence: one sentence using only facts present in the supplied orientation/run

          Mix code, architecture, reliability, product, operator experience, and
          measurement work where the evidence supports it. Do not invent external
          purchases, users, scale numbers, credentials, incidents, or benchmark results.
          Mark an item operator when it depends on a human choice or external service.
          Return only the YAML array. No Markdown fences and no prose.
        PROMPT
      end

      def parse(text)
        body = text.to_s.sub(/\A.*?(?=^- |\A- )/m, "").sub(/\n```.*\z/m, "").strip
        data = YAML.safe_load(body, aliases: false)
        data.is_a?(Array) ? data : []
      rescue Psych::Exception => e
        Master::Ground::Swallow.log(e, context: "Fix::Wishlist.parse")
        []
      end

      def normalize(items)
        items.filter_map do |item|
          next unless item.is_a?(Hash)

          id = slug(item["id"] || item["title"])
          anchor = item["anchor"].to_s.strip
          next if id.empty? || item["title"].to_s.strip.empty? || item["rationale"].to_s.strip.empty?
          next unless valid_anchor?(anchor)

          {
            "id" => id,
            "title" => item["title"].to_s.strip,
            "rationale" => item["rationale"].to_s.strip,
            "anchor" => anchor,
            "change" => item["change"].to_s.strip,
            "effort" => normalize_choice(item["effort"], %w[cheap medium deep], "medium"),
            "reversibility" => normalize_choice(item["reversibility"], %w[reversible guarded operator], "guarded"),
            "implementation" => normalize_choice(item["implementation"], %w[next_fix research operator], "next_fix"),
            "evidence" => item["evidence"].to_s.strip,
          }
        end.uniq { |item| item["id"] }.first(MAX_ITEMS)
      end

      def valid_anchor?(anchor)
        return true if anchor.match?(/\Arun:[a-z_]+\z/i)

        path, line = anchor.split(":", 2)
        return false unless path && line.to_s.match?(/\A\d+\z/)

        candidates = [
          File.expand_path(path, @root),
          File.expand_path(path, File.expand_path("..", @root))
        ]
        candidates.any? { |candidate| File.file?(candidate) }
      end

      def normalize_choice(value, allowed, fallback)
        choice = value.to_s.downcase
        allowed.include?(choice) ? choice : fallback
      end

      def slug(value)
        value.to_s.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_+|_+\z/, "")[0, 64]
      end

      def write_report(items, state:, target:, run_id:)
        FileUtils.mkdir_p(File.dirname(out_file))
        body = [
          "# MASTER wishlist — #{Time.now.utc.iso8601}",
          "",
          "run: #{run_id}",
          "target: #{target}",
          "state: #{state}",
          "items: #{items.size}",
          "",
        ]

        items.each_with_index do |item, index|
          body << "### #{index + 1}. #{item["title"]}"
          body << ""
          body << "#{item["rationale"]} [#{item["effort"]}; #{item["implementation"]}]"
          body << "id: #{item["id"]}"
          body << "anchor: #{item["anchor"]}"
          body << "change: #{item["change"]}"
          body << "evidence: #{item["evidence"]}"
          body << "implementation: #{item["implementation"]}"
          body << "reversibility: #{item["reversibility"]}"
          body << ""
        end

        File.write(out_file, body.join("\n"))
      end
    end
  end
end
