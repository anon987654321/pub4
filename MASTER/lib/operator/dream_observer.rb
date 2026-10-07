# frozen_string_literal: true

require "yaml"
require "fileutils"
require "rbconfig"
require "time"
require_relative "sprawl_census"

module Master
  module Operator
    # Idle observation, not autonomous repair. It turns existing evidence into a
    # tiny ranked queue so MASTER notices neglected structure without inventing work.
    module DreamObserver
      module_function

      QUEUE = ".master/dream_queue.yml"
      MAX_ITEMS = 7

      def observe(root: Master::ROOT)
        items = []
        add_todo(items, root)
        add_sprawl(items, root)
        add_duplicates(items, root)
        add_dirty(items, root)
        items = items.sort_by { |item| [item[:priority].to_i, item[:kind].to_s] }.first(MAX_ITEMS)
        path = File.join(root, QUEUE)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, { version: 1, generated_at: Time.now.utc.iso8601, items: items }.to_yaml)
        items
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "DreamObserver.observe")
        []
      end

      def add_todo(items, root)
        path = File.join(root, "TODO.md")
        return unless File.file?(path)

        File.foreach(path).with_index do |line, index|
          next unless line.match?(/^- [ ]/)

          text = line.sub(/^- [ ]s*/, "").strip
          next if text.empty? || text.match?(/(agent|ignore)/i)
          items << { kind: "todo", priority: 40, source: "TODO.md:#{index + 1}", text: text[0, 220] }
          break if items.count { |item| item[:kind] == "todo" } >= 3
        end
      end

      def add_sprawl(items, root)
        census = ::Operator::SprawlCensus
        counts = census.counts
        ceiling = census.ceilings
        counts.each do |kind, count|
          next unless count > ceiling.fetch(kind, count)

          items << {
            kind: "structure",
            priority: 10,
            source: "sprawl_census",
            text: "#{kind} is #{count}, above ceiling #{ceiling.fetch(kind)}; inspect the named members before moving anything.",
          }
        end
      rescue StandardError
        nil
      end

      def add_duplicates(items, root)
        tool = File.join(root, "MASTER", "tools", "dup_census.rb")
        return unless File.file?(tool)

        out = IO.popen([RbConfig.ruby, tool, "--list"], chdir: root, err: File::NULL, &:read)
        sets = out.to_s.lines.grep(/dup0:/).first(3)
        sets.each do |line|
          text = line.sub(/Adup0:s*/, "").strip
          next if text.empty?
          items << { kind: "duplicate", priority: 20, source: "dup_census", text: text[0, 220] }
        end
      rescue StandardError
        nil
      end

      def add_dirty(items, root)
        out = IO.popen(["git", "-C", root, "status", "--porcelain=v1"], err: File::NULL, &:read)
        paths = out.to_s.lines.map { |line| line[3..].to_s.strip }.reject(&:empty?).first(4)
        return if paths.empty?

        items << {
          kind: "checkout",
          priority: 60,
          source: "git",
          text: "uncommitted work is present; preserve foreign dirt before structural repair: #{paths.join(', ')}",
        }
      end
    end
  end
end
