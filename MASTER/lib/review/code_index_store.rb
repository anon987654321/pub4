# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "prism"

module Master
  module Review
    # Keeps CodeIndex's symbol graph between boots under .master/code_index/.
    #
    # The file records, per source file, the mtime and size it was parsed at, so
    # the next boot re-parses only files that differ. Its name comes from the
    # workspace root, not from the tree hash: a name keyed by the tree hash
    # changes on every edit and leaves nothing to rebuild incrementally from. The
    # tree hash rides inside the file, so an untouched tree is known without
    # comparing a single row. A stamp of the schema, Prism's version and the
    # parser's own source rejects a snapshot made by different parsing logic.
    class CodeIndexStore
      SCHEMA = 1
      REL_DIR = File.join(".master", "code_index").freeze

      def initialize(root:)
        @root = root
        @path = File.join(root, REL_DIR, "#{Digest::SHA256.hexdigest(root)[0, 16]}.json")
      end

      attr_reader :path

      def self.signature(file)
        stat = File.stat(file)
        [(stat.mtime.to_r * 1_000_000_000).to_i, stat.size]
      rescue SystemCallError
        nil
      end

      def self.tree_hash(signatures)
        # A file that vanished between the glob and its stat has a nil signature.
        Digest::SHA256.hexdigest(signatures.sort.map { |file, sig| "#{file}\0#{Array(sig).join(':')}" }.join("\n"))
      end

      # { symbols:, references:, signatures:, tree_hash: } or nil when absent or stale.
      def load
        data = JSON.parse(File.read(@path))
        return unless data["stamp"] == stamp && data["root"] == @root

        files = data["files"]
        {
          symbols: data["symbols"].map { |row| symbol(row, files) },
          references: data["references"].map { |row| reference(row, files) },
          signatures: data["signatures"],
          tree_hash: data["tree_hash"],
        }
      rescue SystemCallError, JSON::ParserError
        nil
      end

      def save(symbols:, references:, signatures:)
        FileUtils.mkdir_p(File.dirname(@path))
        # Files repeat on every row, so rows carry an index into one table.
        files = signatures.keys
        index = files.each_with_index.to_h
        body = {
          stamp:, root: @root, tree_hash: self.class.tree_hash(signatures), signatures:, files:,
          symbols: symbols.map { |s| [s.fqn, s.type, index.fetch(s.file), s.line, s.parent, s.includes] },
          references: references.map { |r| [index.fetch(r.from_file), r.from_line, r.to_fqn, r.ref_type] }
        }
        tmp = "#{@path}.#{Process.pid}.tmp"
        File.write(tmp, JSON.generate(body))
        File.rename(tmp, @path)
      rescue SystemCallError
        FileUtils.rm_f(tmp) if tmp
        nil
      end

      private

      def stamp
        @stamp ||= [SCHEMA, Prism::VERSION, parser_digest]
      end

      def parser_digest
        sources = [File.join(__dir__, "code_index.rb"), File.join(__dir__, "code_index", "symbol_visitor.rb")]
        Digest::SHA256.hexdigest(sources.map { |file| File.read(file) }.join)[0, 16]
      end

      def symbol(row, files)
        CodeIndex::Symbol.new(fqn: row[0], type: row[1].to_sym, file: files[row[2]], line: row[3], parent: row[4], includes: row[5])
      end

      def reference(row, files)
        CodeIndex::Reference.new(from_file: files[row[0]], from_line: row[1], to_fqn: row[2], ref_type: row[3].to_sym)
      end
    end
  end
end
