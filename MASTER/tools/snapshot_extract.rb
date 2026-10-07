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
        match = line.match(/\APack: tree=(\S+) part=(\d+)\/(\d+) /)
        match && { tree: match[1], part: Integer(match[2]), parts: Integer(match[3]) }
      end.first
      raise "snapshot extract: missing Pack header in #{path}" unless pack

      files = []
      current = nil
      fence = nil
      fragment = nil
      total_fragments = nil
      body = []

      flush = lambda do
        return unless current && fence
        files << { path: current, body: body.join, fragment:, total_fragments: }
        current = nil
        fence = nil
        fragment = nil
        total_fragments = nil
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

        if (match = line.match(/^## #{96.chr}(.+?)(?: \[fragment (\d+)\/(\d+)\])?#{96.chr}\s*$/))
          current = match[1]
          fragment = match[2]&.to_i
          total_fragments = match[3]&.to_i
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

      trees = packs.map { |pack| pack.fetch(:tree) }.uniq
      counts = packs.map { |pack| pack.fetch(:parts) }.uniq
      indices = packs.map { |pack| pack.fetch(:part) }.sort
      raise "snapshot extract: mixed trees" unless trees.size == 1
      raise "snapshot extract: inconsistent part counts" unless counts.size == 1
      expected = (1..counts.first).to_a
      raise "snapshot extract: missing or duplicate parts" unless indices == expected

      fragments = Hash.new { |hash, path| hash[path] = [] }
      packs.each do |pack|
        pack.fetch(:files).each do |file|
          fragments[file.fetch(:path)] << [
            file[:fragment],
            file[:total_fragments],
            file.fetch(:body),
          ]
        end
      end

      fragments.each do |relative, pieces|
        fragment_numbers = pieces.filter_map(&:first)
        if fragment_numbers.empty?
          raise "snapshot extract: duplicate source file #{relative}" unless pieces.size == 1
          content = pieces.first.fetch(2)
        else
          total = pieces.map { |piece| piece.fetch(1) }.compact.uniq
          numbers = fragment_numbers.sort
          raise "snapshot extract: incomplete fragments for #{relative}" unless total.size == 1 && numbers == (1..total.first).to_a
          content = pieces.sort_by(&:first).map { |piece| piece.fetch(2) }.join
        end

        target = File.join(root, relative)
        FileUtils.mkdir_p(File.dirname(target))
        File.write(target, content, encoding: "UTF-8")
      end
      fragments.size
    end
 end
end

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
