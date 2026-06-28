# frozen_string_literal: true

module Master
  module Reach
    # Searches cloned documentation, man pages, prompts, and gem references.
    class SearchKnowledge
      TIER = :safe
      NAME = "search_knowledge".freeze
      DESCRIPTION = "Search local knowledge base (ruby_llm docs, OpenBSD man pages, system prompts, gem docs).".freeze
      MAX_RESULTS = 30
      TEXT_EXTENSIONS = %w[.rb .md .txt .yml .yaml .json .sh .conf .html .rst .rdoc].freeze

      def initialize(root:, event_bus: nil)
        @knowledge_root = File.join(File.realpath(root), "knowledge")
        @bus = event_bus
      end

      def call(query:, topic: nil)
        return Result.err("knowledge base not found", category: :validation) unless Dir.exist?(@knowledge_root)

        directory = resolve_search_directory(topic)
        return directory if directory.err?

        results = collect_results(directory.value!, query_regexp(query))
        Result.ok(format_results(results, query, topic))
      rescue StandardError => e
        Result.err("search_knowledge: #{e.message}", category: :unknown)
      end

      def available_topics
        return [] unless Dir.exist?(@knowledge_root)

        Dir.entries(@knowledge_root).select do |entry|
          File.directory?(File.join(@knowledge_root, entry)) && !entry.start_with?(".")
        end
      end

      private

      def resolve_search_directory(topic)
        directory = topic ? File.join(@knowledge_root, topic.to_s) : @knowledge_root
        if Dir.exist?(directory) && File.realpath(directory).start_with?(@knowledge_root)
          return Result.ok(directory)
        end

        Result.err("unknown topic: #{topic}. Available: #{available_topics.join(', ')}", category: :validation)
      end

      def query_regexp(query)
        Regexp.new(query.to_s, Regexp::IGNORECASE)
      rescue RegexpError
        Regexp.new(Regexp.escape(query.to_s), Regexp::IGNORECASE)
      end

      def collect_results(directory, regexp)
        results = []
        search_paths(directory).each do |path|
          results.concat(file_results(path, regexp, MAX_RESULTS - results.size))
          break if results.size >= MAX_RESULTS
        end
        results
      end

      def search_paths(directory)
        Dir.glob(File.join(directory, "**", "*")).select do |path|
          File.file?(path) && text_file?(path) && !skip_file?(path)
        end
      end

      def file_results(path, regexp, limit)
        lines = File.readlines(path, encoding: "UTF-8", invalid: :replace)
        matches = lines.each_index.filter_map do |index|
          next unless lines[index].match?(regexp)

          format_match(path, lines, index)
        end
        matches.first(limit)
      end

      def format_match(path, lines, index)
        first = [index - 2, 0].max
        last = [index + 2, lines.size - 1].min
        snippet = lines[first..last].map.with_index(first + 1) { |line, number| "#{number}: #{line}" }.join
        relative = path.delete_prefix(@knowledge_root + "/")
        "### #{relative}:#{index + 1}\n#{snippet}"
      end

      def format_results(results, query, topic)
        return "No matches for '#{query}' in #{topic || 'all knowledge'}." if results.empty?

        "# Knowledge search: '#{query}' (#{results.size} matches)\n\n#{results.join("\n---\n")}"
      end

      def text_file?(path)
        extension = File.extname(path).downcase
        TEXT_EXTENSIONS.include?(extension) || extension.empty?
      end

      def skip_file?(path)
        path.include?("/.git/") || path.include?("/node_modules/") ||
          path.include?("/vendor/") || File.size(path) > 500_000
      end
    end
  end
end
