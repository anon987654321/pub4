# frozen_string_literal: true

require "ripper"
require_relative "snapshot_minify"

module Operator

  # Reads the written snapshot parts back and proves them against the tree: every tracked text file
  # reassembled from its blocks must equal the file byte for byte (exact variant), or equal its
  # minified text and carry the same Ruby tokens (code variant). A file with no block and no
  # "left out" line is missing. It reads the parts from disk and the tree from git, and shares
  # nothing with the writer but the block format, so a writer that drops files cannot pass.
  module SnapshotVerify
    class Failed < StandardError; end

    HEADING = /\A### (.+?)(?: \(part (\d+) of (\d+), lines (\d+)-(\d+)\))?\n\z/
    FENCE_OPEN = /\A(`{3,})\S*\n\z/
    LEFT_OUT = /\Aleft out \([^)]*\): (.+)\n\z/
    PACK_LINE = /^Pack: tree=(\S+) git=(\S+) part=(\d+)\/(\d+) variant=(\S+)/
    SHOWN = 8
    NOISE = %i[on_comment on_sp on_nl on_ignored_nl on_embdoc_beg on_embdoc on_embdoc_end].freeze

    module_function

    def call(host, tree, variant:, only: nil, io: $stdout)
      parts = read_parts(host, tree, variant)
      problems = []
      blocks, left_out = parse(parts, tree, variant, problems)
      expected = expected_files(host, tree, only, left_out, problems)
      missing = expected.keys - blocks.keys
      problems.concat(missing.first(SHOWN).map { |p| "missing: #{p}" })
      expected.each { |path, text| compare(path, text, blocks[path], variant, problems) if blocks.key?(path) }
      (blocks.keys - expected.keys).first(SHOWN).each { |p| problems << "not in the tree: #{p}" } unless only

      label = variant == :code ? "#{tree} code" : tree
      raise Failed, "snapshot0: #{label} FAILED, #{missing.size} missing, #{problems.size} problem(s)\n#{problems.first(SHOWN).join("\n")}" unless problems.empty?

      Master::Trace::Dmesg.status("snapshot0", "#{label} verified #{expected.size} files, #{missing.size} missing", io:)
      expected.size
    end

    def read_parts(host, tree, variant)
      names = Dir.children(host::REPO).grep(SnapshotParts.stale_pattern(tree)).select { |n| n.include?(".code") == (variant == :code) }
      raise Failed, "snapshot0: #{tree} #{variant} has no snapshot files to verify" if names.empty?

      names.sort.map { |name| [name, File.read(File.join(host::REPO, name), encoding: "UTF-8")] }
    end

    # blocks: path => [[index, total, from, to, body]]; left_out: the paths the header names as left out.
    def parse(parts, tree, variant, problems)
      blocks = Hash.new { |hash, key| hash[key] = [] }
      left_out = []
      seen = []

      parts.each do |name, text|
        meta = text.match(PACK_LINE)
        if meta && meta[1] == tree && meta[5] == variant.to_s
          seen << meta[3].to_i
          problems << "#{name}: expects #{meta[4]} parts, found #{parts.size}" if meta[4].to_i != parts.size
        else
          problems << "#{name}: no Pack line for #{tree} #{variant}"
        end
        read_blocks(name, text, blocks, left_out, problems)
      end

      problems << "parts present #{seen.sort.inspect}, expected 1..#{parts.size}" unless seen.sort == (1..parts.size).to_a
      [blocks, left_out.to_set]
    end

    def read_blocks(name, text, blocks, left_out, problems)
      lines = text.each_line.to_a
      i = lines.index { |l| l.start_with?("## Source") } || lines.size
      left_out.concat(lines[0...i].filter_map { |l| l[LEFT_OUT, 1] })

      while i < lines.size
        heading = lines[i].match(HEADING)
        i += 1
        next unless heading

        markers = []
        until i >= lines.size || lines[i].match?(FENCE_OPEN)
          markers << lines[i]
          i += 1
        end
        fence = lines[i].to_s[FENCE_OPEN, 1]
        (problems << "#{name}: heading #{heading[1]} has no fence") && break unless fence

        i += 1
        body = +""
        until i >= lines.size || lines[i] == "#{fence}\n"
          body << lines[i]
          i += 1
        end
        (problems << "#{name}: block #{heading[1]} is not closed") && break if i >= lines.size

        body.chomp!("\n") if markers.include?("#{SnapshotParts::NO_NEWLINE}\n")
        blocks[heading[1]] << [(heading[2] || 1).to_i, (heading[3] || 1).to_i, heading[4].to_i, heading[5].to_i, body]
        i += 1
      end
    end

    # Tracked text files the pack should hold: the tree's own record, not the writer's. A file the
    # header names as left out must be one the policy leaves out, or not text.
    def expected_files(host, tree, only, left_out, problems)
      files = {}
      SnapshotPack.paths_for(host, tree, only:).each do |path|
        absolute = File.join(host::REPO, path)
        next unless File.file?(absolute) && !host.binary?(absolute)

        text = File.binread(absolute).force_encoding(Encoding::UTF_8)
        if left_out.include?(path)
          problems << "left out without a reason: #{path}" if SnapshotPack.omit_reason(path).nil? && text.valid_encoding?
        elsif text.valid_encoding?
          files[path] = text
        end
      end

      files
    end

    def compare(path, original, pieces, variant, problems)
      sorted = pieces.sort_by(&:first)
      total = sorted.first[1]
      problems << "#{path}: #{sorted.size} blocks of #{total} announced" unless sorted.size == total && sorted.map(&:first) == (1..total).to_a
      problems << "#{path}: line ranges do not follow one another" unless contiguous?(sorted)
      joined = sorted.map(&:last).join
      want = variant == :code ? SnapshotMinify.call(path, original) : original
      return problems << mismatch(path, want, joined) unless joined == want

      problems << "#{path}: Ruby tokens differ from the source" if variant == :code && ruby?(path) && tokens(original) != tokens(joined)
    end

    def contiguous?(sorted)
      return true if sorted.size == 1

      sorted.each_cons(2).all? { |a, b| b[2] == a[3] + 1 }
    end

    def ruby?(path) = SnapshotMinify::HANDLERS[File.extname(path).downcase] == :ruby

    def tokens(source)
      Ripper.lex(source).reject { |_, type, _, _| NOISE.include?(type) }.map { |_, type, tok, _| [type, tok.strip] }.reject { |_, tok| tok.empty? }
    rescue StandardError
      nil
    end

    def mismatch(path, want, got)
      at = (0...[want.bytesize, got.bytesize].min).find { |i| want.getbyte(i) != got.getbyte(i) } || [want.bytesize, got.bytesize].min
      "#{path}: differs at byte #{at} (source #{want.bytesize} bytes, pack #{got.bytesize}) near #{want.byteslice([at - 20, 0].max, 60).inspect}"
    end
  end
end
