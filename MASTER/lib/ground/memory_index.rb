# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"

module Master
  module Ground
    class MemoryIndex
      DEFAULT_DIRS = [
        File.join(Master::ROOT, "data", "claude"),
        File.join(Master::ROOT, ".master", "memory"),
      ].freeze

      attr_reader :root, :index_path

      def initialize(
        root: Master::ROOT,
        dirs: DEFAULT_DIRS,
        index_path: File.join(Master::ROOT, ".master", "memory_index.json")
      )
        @root = root
        @dirs = dirs
        @index_path = index_path
      end

      def rebuild!
        previous = load_index
        docs = files.each_with_object({}) do |path, out|
          body = File.read(path, encoding: "utf-8")
          hash = Digest::SHA256.hexdigest(body)
          rel = relative(path)
          old = previous[rel]
          out[rel] = if old && old["hash"] == hash
                       old
                     else
                       tokenize(body).merge(
                         "hash" => hash, "path" => rel, "title" => title(body, path), "bytes" => body.bytesize
                       )
                     end
        end
        FileUtils.mkdir_p(File.dirname(index_path))
        File.write(index_path, JSON.pretty_generate(docs))
        docs
      end

      def load_index
        return {} unless File.file?(index_path)

        JSON.parse(File.read(index_path, encoding: "utf-8"))
      rescue JSON::ParserError
        {}
      end

      private

      def files
        @dirs.flat_map { |dir| Dir.glob(File.join(dir, "**", "*.md")) }.select { |path| File.file?(path) }
      end

      def tokenize(body)
        terms = body.downcase.scan(/[a-z0-9_\-]{3,}/)
        counts = terms.tally.sort_by { |_term, count| -count }.first(200).to_h
        { "terms" => counts }
      end

      def title(body, path)
        body.lines.find { |line| line.start_with?("#") }&.sub(/^#+\s*/, "")&.strip || File.basename(path)
      end

      def relative(path)
        path.sub(%r{\A#{Regexp.escape(root)}/?}, "")
      end
    end
  end
end
