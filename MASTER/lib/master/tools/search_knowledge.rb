# frozen_string_literal: true

module Master
  module Tools
    # Search the local knowledge base: cloned docs, man pages, system prompts, gem READMEs.
    class SearchKnowledge
      TIER        = :safe
      NAME        = "search_knowledge"
      DESCRIPTION = "Search local knowledge base (ruby_llm docs, OpenBSD man pages, system prompts, gem docs). " \
                    "Use for: how does X work in ruby_llm? what does man pf.conf say? example system prompts?"
      MAX_RESULTS = 30

      def initialize(root:, event_bus: nil)
        @knowledge_root = File.join(File.realpath(root), "knowledge")
        @bus = event_bus
      end

      def call(query:, topic: nil)
        return Result.err("knowledge base not found", category: :validation) unless Dir.exist?(@knowledge_root)

        search_dir = topic ? File.join(@knowledge_root, topic.to_s) : @knowledge_root
        unless Dir.exist?(search_dir)
          return Result.err("unknown topic: #{topic}. Available: #{available_topics.join(", ")}", category: :validation)
        end

        begin
          re = Regexp.new(query, Regexp::IGNORECASE)
        rescue RegexpError => e
          re = Regexp.new(Regexp.escape(query), Regexp::IGNORECASE)
        end

        paths   = Dir.glob(File.join(search_dir, "**", "*")).select { |p| File.file?(p) && text_file?(p) }
        results = []

        paths.each do |path|
          next if skip_file?(path)
          lines = File.readlines(path, encoding: "UTF-8", invalid: :replace)
          lines.each_with_index do |line, idx|
            next unless line.match?(re)
            start  = [idx - 2, 0].max
            finish = [idx + 2, lines.size - 1].min
            ctx    = lines[start..finish].map.with_index(start + 1) { |l, n| "#{n}: #{l}" }.join
            rel    = path.delete_prefix(@knowledge_root + "/")
            results << "### #{rel}:#{idx + 1}\n#{ctx}"
            break if results.size >= MAX_RESULTS
          end
          break if results.size >= MAX_RESULTS
        end

        if results.empty?
          Result.ok("No matches for '#{query}' in #{topic || "all knowledge"}.")
        else
          header = "# Knowledge search: '#{query}' (#{results.size} matches)\n\n"
          Result.ok(header + results.join("\n---\n"))
        end
      rescue => e
        Result.err("search_knowledge: #{e.message}", category: :unknown)
      end

      def available_topics
        return [] unless Dir.exist?(@knowledge_root)
        Dir.entries(@knowledge_root).select { |e| File.directory?(File.join(@knowledge_root, e)) && !e.start_with?(".") }
      end

      private

      def text_file?(path)
        ext = File.extname(path).downcase
        %w[.rb .md .txt .yml .yaml .json .sh .conf .html .rst .rdoc].include?(ext) || ext.empty?
      end

      def skip_file?(path)
        path.include?("/.git/") || path.include?("/node_modules/") ||
          path.include?("/vendor/") || File.size(path) > 500_000
      end
    end
  end
end
