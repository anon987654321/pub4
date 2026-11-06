# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require_relative "../io/exec"

module Operator
  # The deep ratchet rows, remembered by the content of the trees each reads. /fix measures the
  # ratchets before its first repair and again after its last; the 2026-11-05 RAILS run spent 15
  # minutes on the stage before any repair, and a RAILS repair moves no row that reads MASTER alone
  # (selftest, law_trace). A row group whose trees hold the same bytes as when it was last measured
  # answers from here; any change in one of them measures it again.
  #
  # The key of a tree is its committed tree id, its working-tree diff and its untracked files'
  # bytes, so an uncommitted edit counts like a commit. A group that measured an unreadable row is
  # not kept: an instrument that failed once must be asked again. MASTER_RATCHET_CACHE=0 measures
  # every row afresh.
  class RatchetCache
    ROOT = File.expand_path("../../..", __dir__)
    PATH = File.join(ROOT, "MASTER", ".master", "ratchet_cache.json")
    FIELDS = %i[name current ceiling direction source note members].freeze

    def self.enabled? = ENV.fetch("MASTER_RATCHET_CACHE", "1") != "0"

    def self.fetch(group, trees:, row_class:, &) = new.fetch(group, trees:, row_class:, &)

    def initialize(root: ROOT, path: PATH)
      @root = root
      @path = path
    end

    # The rows the block measures, or the rows it measured last over the same trees.
    def fetch(group, trees:, row_class:)
      return yield unless self.class.enabled?

      key = key_for(trees)
      stored = read[group]
      return stored["rows"].map { |row| revive(row, row_class) } if stored && stored["key"] == key

      rows = Array(yield).compact
      write(group, { "key" => key, "rows" => rows.map { |row| dump(row) } }) if rows.all?(&:readable?)
      rows
    end

    def key_for(trees)
      prints = Array(trees).map(&:to_s).sort.uniq.map { |tree| tree_digest(tree) }
      Digest::SHA256.hexdigest(prints.join("\0"))
    end

    private

    def tree_digest(tree)
      head, = git("rev-parse", "HEAD:#{tree}")
      diff, = git("diff", "HEAD", "--binary", "--", tree)
      listing, = git("ls-files", "--others", "--exclude-standard", "-z", "--", tree)
      untracked = listing.split("\0").reject(&:empty?).sort.map { |relative| file_print(relative) }
      Digest::SHA256.hexdigest([tree, head.strip, Digest::SHA256.hexdigest(diff), *untracked].join("\0"))
    end

    def git(*args) = Master::Io::Exec.capture2("git", "-C", @root, *args)

    def file_print(relative)
      path = File.join(@root, relative)
      File.file?(path) ? "#{relative}\0#{Digest::SHA256.file(path).hexdigest}" : "#{relative}\0missing"
    end

    # A missing or torn cache file is an empty cache: every group is measured.
    def read
      return {} unless File.file?(@path)

      data = JSON.parse(File.read(@path))
      data.is_a?(Hash) ? data : {}
    rescue JSON::ParserError => e
      warn "ratchet cache unreadable, measuring afresh: #{e.message[0, 80]}"
      {}
    end

    def write(group, entry)
      data = read.merge(group => entry)
      FileUtils.mkdir_p(File.dirname(@path))
      temporary = "#{@path}.#{Process.pid}.tmp"
      File.write(temporary, JSON.generate(data))
      File.rename(temporary, @path)
    rescue SystemCallError => e
      warn "ratchet cache not written: #{e.class}: #{e.message}"
    end

    def dump(row)
      FIELDS.to_h { |field| [field.to_s, field == :direction ? row.direction.to_s : row.public_send(field)] }
    end

    def revive(stored, row_class)
      values = FIELDS.to_h { |field| [field, stored[field.to_s]] }
      values[:direction] = values[:direction]&.to_sym
      row_class.new(**values)
    end
  end
end
