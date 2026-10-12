# frozen_string_literal: true

require "fileutils"
require_relative "snapshot_map"
require_relative "snapshot_minify"
require_relative "snapshot_split"

module Operator

  # The full source of a tree as numbered parts, each small enough to upload to a model whose
  # context is smaller than the tree. Files travel whole, in reading order; one larger than a part
  # is cut by SnapshotSplit into blocks that rejoin to the file byte for byte. Every part opens
  # with the same header and the complete Map, so a reader holding one part knows where the rest are.
  #
  # Two variants: the exact source, and the code variant that SnapshotMinify has stripped of comments.
  module SnapshotParts
    # One file per tree unless --part-bytes or MASTER_SNAPSHOT_PART_BYTES asks for parts: a pack is never
    # truncated, and 64 MB holds every governed tree whole.
    DEFAULT_PART_BYTES = 64_000_000
    # Heading, fences and markers around a block's body.
    BLOCK_OVERHEAD = 400
    # A part this small has no room for source once the Map is paid for.
    MIN_ROOM = 1_000
    # A big file starts in the room left in a part only when that is at least this fraction of a part.
    MIN_FILL = 4
    VARIANTS = %i[exact code].freeze
    NO_NEWLINE = "[no trailing newline]"
    FROM_PREVIOUS = "[continues from the previous block]"
    INTO_NEXT = "[continued in the next block]"

    Unit = Struct.new(:path, :text, keyword_init: true)

    module_function

    # snapshot_T.md, or snapshot_T.part01-of-03.md; the code variant adds ".code" after the tree.
    def file_names(tree, variant, count)
      base = variant == :code ? "snapshot_#{tree}.code" : "snapshot_#{tree}"
      return ["#{base}.md"] if count == 1

      width = [2, count.to_s.size].max
      (1..count).map { |k| "#{base}.part#{k.to_s.rjust(width, '0')}-of-#{count.to_s.rjust(width, '0')}.md" }
    end

    # Every snapshot file the tree has at the repo root: single, parts, either variant, and the mirror's parts.
    def stale_pattern(tree) = /\Asnapshot_#{Regexp.escape(tree)}(\.code)?(\.part\d+(-of-\d+)?)?\.md\z/

    def block(path, body, index: 1, total: 1, first_line: 1)
      longest = body.scan(/^`{3,}/).map(&:length).max.to_i
      fence = "`" * [3, longest + 1].max
      lang = SnapshotPack::FENCE_LANG.fetch(File.extname(path).downcase, "")
      last = first_line + body.count("\n") - (body.end_with?("\n") || body.empty? ? 1 : 0)
      out = +"### #{path}"
      out << " (part #{index} of #{total}, lines #{first_line}-#{last})" if total > 1
      out << "\n"
      out << "#{FROM_PREVIOUS}\n" if index > 1
      out << "#{NO_NEWLINE}\n" if !body.empty? && !body.end_with?("\n")
      out << "#{fence}#{lang}\n#{body}"
      out << "\n" if !body.empty? && !body.end_with?("\n")
      out << "#{fence}\n"
      out << "#{INTO_NEXT}\n" if index < total
      out << "\n"
    end

    # Readable text files, split into those packed and those named as left out. Binary files are counted.
    def collect(host, paths, variant)
      entries = []
      omitted = Hash.new { |hash, key| hash[key] = [] }

      paths.each do |path|
        absolute = File.join(host::REPO, path)
        next unless File.file?(absolute)
        next omitted["binary"] << path if host.binary?(absolute)

        reason = SnapshotPack.omit_reason(path)
        next omitted[reason] << path if reason

        text = File.binread(absolute).force_encoding(Encoding::UTF_8)
        next omitted["not valid UTF-8"] << path unless text.valid_encoding?

        entries << entry(path, text, variant)
      end

      [SnapshotPack.rank_centrality(entries), omitted]
    end

    def entry(path, text, variant)
      code = SnapshotMinify.call(path, text)
      body = variant == :code ? code : text

      { path:, original: text, minified: code, body:, block: block(path, body) }
    end

    def reading_order(entries) = entries.sort_by { |f| SnapshotPack.reading_order(f) }

    # The pieces of one file: one block when it fits, else consecutive blocks cut at SnapshotSplit
    # boundaries, the first sized to the room left in the part it starts in.
    def pieces(file, room, left)
      cut = SnapshotSplit.chunks(file[:path], file[:body], room - BLOCK_OVERHEAD, first: left - BLOCK_OVERHEAD)
      line = 1
      cut.each_with_index.map do |piece, i|
        text = block(file[:path], piece, index: i + 1, total: cut.size, first_line: line)
        line += piece.count("\n") + (piece.end_with?("\n") || piece.empty? ? 0 : 1)
        Unit.new(path: file[:path], text:)
      end
    end

    # Greedy in reading order: a part closes when the next file would overflow it. A file larger than a
    # whole part starts in the room left, when that is worth having, rather than leaving it empty.
    def assign(files, room)
      parts = [[]]
      used = 0
      files.each do |file|
        size = file[:block].bytesize
        left = room - used
        units = if size <= left then [Unit.new(path: file[:path], text: file[:block])]
                elsif size <= room then nil
                elsif left >= room / MIN_FILL then pieces(file, room, left)
                end
        if units.nil?
          parts << []
          used = 0
          units = size <= room ? [Unit.new(path: file[:path], text: file[:block])] : pieces(file, room, room)
        end
        units.each do |unit|
          if used.positive? && used + unit.text.bytesize > room
            parts << []
            used = 0
          end
          parts.last << unit
          used += unit.text.bytesize
        end
      end
      parts
    end

    def part_tag(first, last, width)
      one = first.to_s.rjust(width, "0")
      first == last ? "p#{one}" : "p#{one}-#{last.to_s.rjust(width, '0')}"
    end

    def omitted_lines(omitted)
      listed = omitted.reject { |reason, _| reason == "binary" }.sort
      return "" if listed.empty?

      "\n#{listed.flat_map { |reason, list| list.sort.map { |p| "left out (#{reason}): #{p}" } }.join("\n")}\n"
    end

    def guide(tree, variant, count)
      kind = variant == :code ? "code-only" : "exact"
      stripped = variant == :code ? " Comments and blank lines are removed (a file's first comment stays as one purpose line) and nothing else changes." : ""
      "Reading guide: this is the #{kind} source of the #{tree} tree in #{count == 1 ? "one part" : "#{count} parts"}, cut at file boundaries so each part fits an upload. " \
        "Every tracked text file appears once, whole, under its own `### path` heading in reading order (the constitution and entry points first, tests last); " \
        "the Map below lists every file with the part that holds it (`p03`, or `p03-04` for a file continued across parts). " \
        "A file larger than a part is cut only between top-level constructs into consecutive blocks headed `(part k of m, lines a-b)`; " \
        "join its blocks in order, adding nothing, to get the file byte for byte. Nothing is truncated or summarised.#{stripped} " \
        "Files with no reading value are named under Omitted. Work through the map first, then read the parts you need."
    end

    # Identical in every part but the part line.
    def header(job, part, count, map)
      width = [2, count.to_s.size].max
      sha = job[:sha]
      files = job[:files].size
      out = +"# #{job[:tree]} — source snapshot, part #{part.to_s.rjust(width, '0')} of #{count.to_s.rjust(width, '0')}\n\n"
      out << "Pack: tree=#{job[:tree]} git=#{sha} part=#{part}/#{count} variant=#{job[:variant]} files=#{files} "
      out << "omitted=#{job[:omitted].values.sum(&:size)} budget=full\n\n"
      out << "#{guide(job[:tree], job[:variant], count)}\n\n"
      out << SnapshotPack.omitted_note(job[:omitted])
      out << "## Map\n\n#{map}#{omitted_lines(job[:omitted])}\n## Source (part #{part} of #{count})\n\n"
    end

    # Build the parts in memory: [[file name, text] ...]. Raises when the part size leaves no room for source.
    def build(host, tree, paths, variant:, part_bytes:)
      files, omitted = collect(host, paths, variant)
      job = { tree:, variant:, files:, omitted:, sha: host.head_sha }
      ordered = reading_order(files)
      everywhere = ordered.to_set { |f| f[:path] }
      widest = SnapshotMap.map_text(ordered, everywhere, tag: ->(_) { "p00-00" })
      room = part_bytes - header(job, 99, 99, widest).bytesize
      raise "snapshot: #{tree} part size #{part_bytes} leaves no room after the Map (#{part_bytes - room} bytes)" if room < MIN_ROOM

      groups = assign(ordered, room)
      names = file_names(tree, variant, groups.size)
      map = SnapshotMap.map_text(ordered, everywhere, tag: tagger(groups, names.size))
      rendered = groups.each_with_index.map do |group, i|
        text = header(job, i + 1, groups.size, map) + group.map(&:text).join
        text << "## End of part #{i + 1} of #{groups.size}\n"
        [names[i], text]
      end

      [rendered, job]
    end

    def tagger(groups, count)
      width = [2, count.to_s.size].max
      span = Hash.new { |hash, key| hash[key] = [] }
      groups.each_with_index { |group, i| group.each { |unit| span[unit.path] << i + 1 } }

      ->(file) { part_tag(span.fetch(file[:path]).min, span.fetch(file[:path]).max, width) }
    end

    def write(host, tree, paths:, variant:, part_bytes:, io: $stdout)
      rendered, = build(host, tree, paths, variant:, part_bytes:)
      rendered.each do |name, text|
        File.write(File.join(host::REPO, name), text, encoding: "UTF-8")
        Master::Trace::Dmesg.status("snapshot0", "#{tree}, #{name}, #{text.bytesize} bytes (~#{text.bytesize / 4000}K tokens)", io:)
      end

      rendered.map { |name, _| File.join(host::REPO, name) }
    end
  end
end
