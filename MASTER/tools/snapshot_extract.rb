# frozen_string_literal: true

require "fileutils"
require "optparse"
require "tmpdir"
require_relative "../lib/trace/dmesg"

# Rehydrates the source files embedded in one or more snapshot packs into a
# temporary repository-shaped tree. It never invents missing binaries or claim
# the result is a byte-identical checkout; it restores exactly the text files
# the snapshot contains.
module Operator
  module SnapshotExtract
    module_function

    def parse(path)
      lines = File.readlines(path, encoding: "UTF-8")
      pack = lines.filter_map do |line|
        match = line.match(/\APack: tree=(\S+) git=(\S+) part=(\d+)\/(\d+) /)
        match && { tree: match[1], git: match[2], part: Integer(match[3]), parts: Integer(match[4]) }
      end.first
      raise "snapshot extract: missing Pack header in #{path}" unless pack

      files = []
      current = nil
      fence = nil
      fragment = nil
      total_fragments = nil
      @bytes = nil
      @newline = nil
      body = []

      flush = lambda do
        return unless current && fence
        files << { path: current, body: body.join, fragment:, total_fragments:, bytes: @bytes, newline: @newline }
        current = nil
        fence = nil
        fragment = nil
        total_fragments = nil
        @bytes = nil
        @newline = nil
        body = []
      end

      lines.each do |line|
        if fence
          if line.chomp == fence
            flush.call
          else
            body << line
          end
          next
        end

        if (match = line.match(/^## #{96.chr}(.+?) \[bytes=(\d+) newline=(0|1)\]#{96.chr}\s*$/))
          current = match[1]
          fragment = nil
          total_fragments = nil
          @bytes = Integer(match[2])
          @newline = Integer(match[3])
          next
        end

        if (match = line.match(/^## #{96.chr}(.+?) \[fragment (\d+)\/(\d+) bytes=(\d+) newline=(0|1)\]#{96.chr}\s*$/))
          current = match[1]
          fragment = Integer(match[2])
          total_fragments = Integer(match[3])
          @bytes = Integer(match[4])
          @newline = Integer(match[5])
          next
        end

        next unless current && (match = line.match(/^(`{3,})[A-Za-z0-9_-]*\s*$/))
        fence = match[1]
        body = []
      end

      raise "snapshot extract: unterminated block in #{path}" if current || fence
      pack.merge(files:)
    end

    def write(packs, root)
      raise "snapshot extract: no packs" if packs.empty?

      revisions = packs.map { |pack| pack.fetch(:git) }.uniq
      raise "snapshot extract: mixed git revisions" unless revisions.size == 1

      total = 0
      packs.group_by { |pack| pack.fetch(:tree) }.each do |tree, tree_packs|
        counts = tree_packs.map { |pack| pack.fetch(:parts) }.uniq
        indices = tree_packs.map { |pack| pack.fetch(:part) }.sort
        raise "snapshot extract: inconsistent part counts for #{tree}" unless counts.size == 1
        expected = (1..counts.first).to_a
        raise "snapshot extract: missing or duplicate parts for #{tree}" unless indices == expected

        fragments = Hash.new { |hash, path| hash[path] = [] }
        tree_packs.each do |pack|
          pack.fetch(:files).each do |file|
            fragments[file.fetch(:path)] << [
              file[:fragment],
              file[:total_fragments],
              file.fetch(:bytes),
              file.fetch(:newline),
              file.fetch(:body),
            ]
          end
        end

        fragments.each do |relative, pieces|
          expected_prefix = "#{tree}/"
          raise "snapshot extract: path escapes declared tree #{relative}" unless relative.start_with?(expected_prefix)
          fragment_numbers = pieces.filter_map(&:first)
          if fragment_numbers.empty?
            raise "snapshot extract: duplicate source file #{relative}" unless pieces.size == 1
            content = pieces.first.fetch(4)
            content = content.delete_suffix("\n") if pieces.first.fetch(3).zero?
          else
            total_fragments = pieces.map { |piece| piece.fetch(1) }.compact.uniq
            numbers = fragment_numbers.sort
            raise "snapshot extract: incomplete fragments for #{relative}" unless total_fragments.size == 1 && numbers == (1..total_fragments.first).to_a
            content = pieces.sort_by(&:first).map do |piece|
              body = piece.fetch(4)
              piece.fetch(3).zero? ? body.delete_suffix("\n") : body
            end.join
          end
          declared = pieces.sum { |piece| piece.fetch(2) }
          raise "snapshot extract: byte count mismatch for #{relative}" unless content.bytesize == declared

          target = File.join(root, relative)
          FileUtils.mkdir_p(File.dirname(target))
          File.write(target, content, encoding: "UTF-8")
        end
        total += fragments.size
      end
      total
    end

nd
 end
end

if $PROGRAM_NAME == __FILE__
  options = {}
  OptionParser.new do |opts|
    opts.banner = "Usage: ruby snapshot_extract.rb [--to DIR] SNAPSHOT.md..."
    opts.on("--to DIR") { |dir| options[:root] = dir }
  end.parse!(ARGV)

  if ARGV.empty?
    Master::Trace::Dmesg.status("snapshot0", "give at least one snapshot", io: $stderr)
    exit 64
  end
  root = File.expand_path(options.fetch(:root, Dir.mktmpdir("master-snapshot-")))
  FileUtils.mkdir_p(root)

  packs = ARGV.map { |path| Operator::SnapshotExtract.parse(path) }
  count = Operator::SnapshotExtract.write(packs, root)

  Master::Trace::Dmesg.status("snapshot0", "rehydrated #{count} text file(s) into #{root}")

end
