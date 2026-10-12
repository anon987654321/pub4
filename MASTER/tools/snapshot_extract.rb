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
    VALID_TREES = %w[MASTER RAILS OPENBSD STUDIO].freeze

    module_function

    def parse(path)
      lines = File.readlines(path, encoding: "UTF-8")
      headers = lines.filter_map do |line|
        match = line.match(
          /\APack: tree=(\S+) git=(\S+) part=(\d+)\/(\d+) text_total=(\d+) fragments_total=(\d+) binary=(\d+) omitted=(\d+) files_in_part=(\d+) fragments_in_part=(\d+) max_bytes=(\d+)\s*\z/,
        )
        next unless match

        {
          tree: match[1],
          git: match[2],
          part: Integer(match[3]),
          parts: Integer(match[4]),
          text_total: Integer(match[5]),
          fragments_total: Integer(match[6]),
          binary: Integer(match[7]),
          omitted: Integer(match[8]),
          files_in_part: Integer(match[9]),
          fragments_in_part: Integer(match[10]),
          max_bytes: Integer(match[11]),
        }
      end
      raise "snapshot extract: missing or malformed Pack header in #{path}" unless headers.one?
      pack = headers.fetch(0)
      unless VALID_TREES.include?(pack[:tree])
        raise "snapshot extract: unknown tree #{pack[:tree].inspect} in #{path}"
      end
      unless pack[:parts].positive? && pack[:part].between?(1, pack[:parts]) && pack[:omitted].zero?
        raise "snapshot extract: invalid or incomplete Pack header in #{path}"
      end

      files = []
      current = nil
      fence = nil
      fragment = nil
      total_fragments = nil
      bytes = nil
      newline = nil
      body = []

      flush = lambda do
        return unless current && fence
        files << { path: current, body: body.join, fragment:, total_fragments:, bytes:, newline: }
        current = nil
        fence = nil
        fragment = nil
        total_fragments = nil
        bytes = nil
        newline = nil
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
          bytes = Integer(match[2])
          newline = Integer(match[3])
          next
        end

        if (match = line.match(/^## #{96.chr}(.+?) \[fragment (\d+)\/(\d+) bytes=(\d+) newline=(0|1)\]#{96.chr}\s*$/))
          current = match[1]
          fragment = Integer(match[2])
          total_fragments = Integer(match[3])
          bytes = Integer(match[4])
          newline = Integer(match[5])
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

      FileUtils.mkdir_p(root)
      root = File.realpath(root)
      packs.each do |pack|
        valid_header = VALID_TREES.include?(pack[:tree]) &&
                       pack[:part].is_a?(Integer) && pack[:parts].is_a?(Integer) &&
                       pack[:parts].positive? && pack[:part].between?(1, pack[:parts]) &&
                       %i[text_total fragments_total binary omitted files_in_part fragments_in_part max_bytes].all? do |key|
                         pack[key].is_a?(Integer) && pack[key] >= 0
                       end && pack[:max_bytes].positive? && pack[:omitted].zero?
        raise "snapshot extract: invalid or incomplete Pack header" unless valid_header
      end
      revisions = packs.map { |pack| pack.fetch(:git) }.uniq
      raise "snapshot extract: mixed git revisions" unless revisions.size == 1

      total = 0
      packs.group_by { |pack| pack.fetch(:tree) }.each do |tree, tree_packs|
        raise "snapshot extract: unknown tree #{tree.inspect}" unless VALID_TREES.include?(tree)

        counts = tree_packs.map { |pack| pack.fetch(:parts) }.uniq
        indices = tree_packs.map { |pack| pack.fetch(:part) }.sort
        text_totals = tree_packs.map { |pack| pack.fetch(:text_total) }.uniq
        fragment_totals = tree_packs.map { |pack| pack.fetch(:fragments_total) }.uniq
        binary_totals = tree_packs.map { |pack| pack.fetch(:binary) }.uniq
        omitted_totals = tree_packs.map { |pack| pack.fetch(:omitted) }.uniq
        raise "snapshot extract: inconsistent part counts for #{tree}" unless counts.size == 1
        raise "snapshot extract: inconsistent text totals for #{tree}" unless text_totals.size == 1
        raise "snapshot extract: inconsistent fragment totals for #{tree}" unless fragment_totals.size == 1
        raise "snapshot extract: inconsistent binary totals for #{tree}" unless binary_totals.size == 1
        raise "snapshot extract: omitted files declared for #{tree}" unless omitted_totals == [0]
        expected = (1..counts.first).to_a
        raise "snapshot extract: missing or duplicate parts for #{tree}" unless indices == expected
        raise "snapshot extract: expected #{counts.first} part(s), got #{tree_packs.size} for #{tree}" unless tree_packs.size == counts.first

        fragments = Hash.new { |hash, path| hash[path] = [] }
        tree_packs.each do |pack|
          files = pack.fetch(:files)
          paths = files.map { |file| file.fetch(:path) }
          raise "snapshot extract: files_in_part mismatch for #{tree} part #{pack.fetch(:part)}" unless paths.uniq.size == pack.fetch(:files_in_part)
          raise "snapshot extract: fragments_in_part mismatch for #{tree} part #{pack.fetch(:part)}" unless files.size == pack.fetch(:fragments_in_part)
          files.each do |file|
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
          segments = relative.split("/", -1)
          safe_path = segments.first == tree &&
                      segments.none? { |segment| segment.empty? || segment == "." || segment == ".." } &&
                      !relative.include?("\\")
          target_root = File.expand_path(root)
          target_path = File.expand_path(relative, target_root)
          safe_path &&= target_path.start_with?(target_root + File::SEPARATOR)
          raise "snapshot extract: path escapes declared tree #{relative}" unless safe_path
          fragment_numbers = pieces.filter_map(&:first)
          if fragment_numbers.empty?
            raise "snapshot extract: duplicate source file #{relative}" unless pieces.size == 1
            content = pieces.first.fetch(4)
            content = content.delete_suffix("\n") if pieces.first.fetch(3).zero?
          else
            total_fragments = pieces.filter_map { |piece| piece.fetch(1) }.uniq
            numbers = fragment_numbers.sort
            raise "snapshot extract: incomplete fragments for #{relative}" unless total_fragments.size == 1 && numbers == (1..total_fragments.first).to_a
            content = pieces.sort_by(&:first).map do |piece|
              body = piece.fetch(4)
              piece.fetch(3).zero? ? body.delete_suffix("\n") : body
            end.join
          end
          declared = pieces.sum { |piece| piece.fetch(2) }
          raise "snapshot extract: byte count mismatch for #{relative}" unless content.bytesize == declared

          target = File.expand_path(relative, root)
          directory = root
          segments[0...-1].each do |segment|
            directory = File.join(directory, segment)
            raise "snapshot extract: refuses symlink directory #{directory}" if File.symlink?(directory)

            FileUtils.mkdir_p(directory)
          end
          raise "snapshot extract: refuses symlink file #{target}" if File.symlink?(target)

          File.write(target, content, encoding: "UTF-8")
        end
        expected_text_total = text_totals.fetch(0)
        expected_fragment_total = fragment_totals.fetch(0)
        raise "snapshot extract: text file count mismatch for #{tree}" unless fragments.size == expected_text_total
        raise "snapshot extract: fragment count mismatch for #{tree}" unless fragments.values.sum(&:size) == expected_fragment_total
        total += fragments.size
      end
      total
    end
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
