# frozen_string_literal: true

require "fileutils"

module Master
  module Reach
    # MemoryRecord — LLM-callable tool that writes a markdown memory record
    # to data/claude/<key>.md, updates the MEMORY.md index, and seeds the
    # in-process Master::Ground::Memory store so semantic recall sees it now.
    # Types: user, feedback, project, reference, general.
    class MemoryRecord
      TIER        = :open
      NAME        = "memory_record".freeze
      DESCRIPTION = "Write a durable markdown memory record. " \
                    "Use for user facts, feedback, project context, or external references.".freeze

      VALID_TYPES = %w[user feedback project reference general].freeze
      KEY_RE      = /\A[a-z0-9][a-z0-9_]{1,60}\z/.freeze

      def initialize(memory:, root: Dir.pwd, event_bus: nil)
        @memory = memory
        @root   = root
        @bus    = event_bus
      end

      def call(key:, description:, body:, type: "general")
        key  = key.to_s.strip.downcase
        type = VALID_TYPES.include?(type.to_s) ? type.to_s : "general"
        return Result.err("memory_record: key must match #{KEY_RE.source}", category: :validation) unless KEY_RE.match?(key)
        return Result.err("memory_record: body required", category: :validation) if body.to_s.strip.empty?

        path = File.join(@root, "data", "claude", "#{key}.md")
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, render(key:, description:, type:, body:))
        update_index(key:, description:)
        @memory&.remember("claude/#{key}", body.to_s.strip, type: type)
        @bus&.publish("memory:record", key: key, type: type, path: relative(path))
        Result.ok("memory_record: #{relative(path)}")
      rescue StandardError => e
        Result.err("memory_record: #{e.message}", category: :unknown)
      end

      private

      def render(key:, description:, type:, body:)
        <<~MD
          ---
          name: #{key.tr("_", " ")}
          description: #{description.to_s.strip}
          type: #{type}
          ---

          #{body.to_s.strip}
        MD
      end

      def update_index(key:, description:)
        index = File.join(@root, "data", "claude", "MEMORY.md")
        FileUtils.mkdir_p(File.dirname(index))
        File.write(index, "# Memory Index\n\n") unless File.exist?(index)
        line  = "- [#{key.tr("_", " ")}](#{key}.md) — #{description.to_s.strip}"
        lines = File.read(index).split("\n", -1)
        return if lines.any? { |l| l.include?("](#{key}.md)") }
        lines << line
        File.write(index, lines.join("\n"))
      end

      def relative(path) = path.sub("#{@root}/", "")
    end
  end
end
