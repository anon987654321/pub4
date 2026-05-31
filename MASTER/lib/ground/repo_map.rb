# frozen_string_literal: true

module Master
  module Ground
    class RepoMap
      DEFAULT_IGNORES = %w[
        .git tmp log vendor node_modules coverage .bundle storage public/assets
        knowledge/awesome knowledge/vendor
      ].freeze

      LANGUAGE_BY_EXT = {
        ".rb" => :ruby,
        ".js" => :javascript,
        ".ts" => :typescript,
        ".css" => :css,
        ".html" => :html,
        ".erb" => :erb,
        ".yml" => :yaml,
        ".yaml" => :yaml,
        ".json" => :json,
        ".md" => :markdown,
        ".sh" => :shell
      }.freeze

      FileEntry = Struct.new(:path, :language, :bytes, :mtime, :score, keyword_init: true)

      attr_reader :root

      def initialize(root: Master::ROOT, ignores: DEFAULT_IGNORES)
        @root = root
        @ignores = ignores
      end

      def files
        Dir.glob(File.join(root, "**", "*"), File::FNM_DOTMATCH)
           .select { |path| File.file?(path) }
           .reject { |path| ignored?(path) }
           .map { |path| entry(path) }
      end

      def relevant(query, limit: 30)
        terms = query.to_s.downcase.scan(/[a-z0-9_\-]+/)
        files.map do |entry|
          text = entry.path.downcase
          bonus = terms.sum { |term| text.include?(term) ? 3 : 0 }
          lang_bonus = entry.language == :ruby ? 1 : 0
          entry.score = bonus + lang_bonus - size_penalty(entry.bytes)
          entry
        end.sort_by { |entry| -entry.score }.first(limit)
      end

      def brief(query = nil, limit: 20)
        rows = query ? relevant(query, limit: limit) : files.first(limit)
        rows.map { |entry| "#{entry.path} #{entry.language} #{entry.bytes}B score=#{format('%.2f', entry.score || 0)}" }
      end

      private

      def entry(path)
        FileEntry.new(
          path: relative(path),
          language: LANGUAGE_BY_EXT.fetch(File.extname(path), :other),
          bytes: File.size(path),
          mtime: File.mtime(path),
          score: 0
        )
      end

      def ignored?(path)
        rel = relative(path)
        @ignores.any? { |ignore| rel == ignore || rel.start_with?("#{ignore}/") }
      end

      def relative(path)
        path.sub(%r{\A#{Regexp.escape(root)}/?}, "")
      end

      def size_penalty(bytes)
        return 0 if bytes < 20_000
        Math.log(bytes / 20_000.0)
      end
    end
  end
end
