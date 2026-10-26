# frozen_string_literal: true

require "fileutils"
require_relative "../io/exec"
require_relative "../trace/dmesg"

module Operator
  # One word renamed wherever it is a name: in file contents and in file paths, in its three spellings (gate,
  # Gate, GATE) and their plurals, over the tracked files of the repository. A match is a whole name part, so
  # snake_case, CamelCase and SCREAMING_CASE parts count and a word that merely contains it (aggregate,
  # navigate, gateway) does not. A sed over every file, which the old replace.sh was, cannot tell them apart.
  #
  # A word can have a second meaning the rename must not reach: renaming gate to check on 2026-10-22 had to
  # leave dilla's note gate and postpro's film gate weave alone. --keep names those spellings, and --skip the
  # paths whose every use is the other meaning.
  class WordRename
    Change = Data.define(:from, :to, :text)

    USAGE = "usage: ruby MASTER/tools/rename.rb --word OLD NEW [--keep=a,b] [--skip=path/,path/] [--apply]"

    # What the rename would touch, and with --apply the rename itself, refused over a dirty tree or a move
    # onto a path that is taken.
    def self.cli(args, root:, dirty:)
      words = args.reject { |arg| arg.start_with?("--") }
      return warn(USAGE) || 64 unless words.size == 2

      listed = ->(flag) { args.find { |arg| arg.start_with?("--#{flag}=") }.to_s.split("=", 2).last.to_s.split(",") }
      renamer = new(*words, root:, keep: listed.("keep"), skip: listed.("skip"))
      found = renamer.changes
      clashes = renamer.collisions(found)
      report(found, clashes)
      return 0 unless args.include?("--apply")

      refusal = clashes.any? ? "moves land on taken paths" : ("#{dirty.size} uncommitted changes" if dirty.any?)
      return status("refused, #{refusal}; nothing written") || 1 if refusal

      renamer.apply!(found)
      status("wrote #{found.size} files; run the suites, a rename that parses is not a rename that works") || 0
    end

    def self.report(found, clashes)
      moves = found.reject { |change| change.from == change.to }
      status("#{found.size} files change, #{moves.size} of them move")
      moves.first(20).each { |change| status("#{change.from} -> #{change.to}") }
      clashes.each { |change| status("CLASH #{change.from} -> #{change.to}, which exists") }
    end

    def self.status(line) = Master::Trace::Dmesg.status("rename0", line) && nil

    def initialize(old_word, new_word, root:, keep: [], skip: [])
      @old = old_word.downcase
      @new = new_word.downcase
      @root = root
      @keep = keep
      @skip = skip
    end

    def changes = tracked.filter_map { |path| change_for(path) }

    # The text with every spelling of the word renamed, the kept spellings left as they were.
    def rename(text)
      kept = {}
      text = @keep.each_with_index.reduce(text) do |out, (word, index)|
        out.gsub(word) { kept["\u0000#{index}\u0000"] = word; "\u0000#{index}\u0000" }
      end
      text = spellings.reduce(text) { |out, (pattern, spelling)| out.gsub(pattern, spelling) }
      kept.reduce(text) { |out, (mark, word)| out.gsub(mark, word) }
    end

    # Moves that land on a path another tracked file already holds.
    def collisions(found) = found.select { |change| change.from != change.to && tracked.include?(change.to) }

    def apply!(found)
      found.each { |change| write(change) }
      found.map { |change| File.dirname(File.join(@root, change.from)) }.uniq.each { |dir| prune(dir) }
    end

    private

    def spellings
      [[@old, @new, "a-z", "A-Za-z"], [@old.capitalize, @new.capitalize, "a-z", "A-Z"],
       [@old.upcase, @new.upcase, "A-Z", "A-Z"]].map do |from, to, tail, head|
        plural = tail == "A-Z" ? "S" : "s"
        # After a regex escape (\A, \b, \n) the letter belongs to the escape: %r{\Agates\d+} was missed once.
        [/(?:(?<![#{head}])|(?<=\\[A-Za-z]))#{Regexp.escape(from)}(?=#{plural}?(?![#{tail}]))/, to]
      end
    end

    def tracked
      @tracked ||= begin
        out, status = Master::Io::Exec.capture2("git", "-C", @root, "ls-files", "-z")
        raise "rename: git ls-files failed" unless status.success?

        out.split("\0").reject { |path| @skip.any? { |prefix| path.start_with?(prefix) } }
      end
    end

    def change_for(path)
      full = File.join(@root, path)
      return unless File.file?(full)

      text = binary?(full) ? nil : File.read(full, encoding: "UTF-8", invalid: :replace, undef: :replace)
      renamed = text && rename(text)
      to = rename(path)
      Change.new(from: path, to:, text: renamed) unless to == path && renamed == text
    end

    def binary?(path) = File.binread(path, 8192).to_s.include?("\0")

    def write(change)
      from = File.join(@root, change.from)
      to = File.join(@root, change.to)
      FileUtils.mkdir_p(File.dirname(to))
      mode = File.stat(from).mode
      change.text ? File.write(to, change.text) : FileUtils.cp(from, to)
      File.chmod(mode, to)
      File.delete(from) unless from == to
    end

    def prune(dir)
      while dir.start_with?(@root) && dir != @root && Dir.exist?(dir) && Dir.empty?(dir)
        Dir.rmdir(dir)
        dir = File.dirname(dir)
      end
    end
  end
end
