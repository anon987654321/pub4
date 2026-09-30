# frozen_string_literal: true

require "fileutils"
require "optparse"
require "tmpdir"

# Rehydrates the source files embedded in one or more snapshot packs into a
# temporary repository-shaped tree. It never invents missing binaries or claim
# the result is a byte-identical checkout; it restores exactly the text files
# the snapshot contains.
module Operator
  module SnapshotExtract
    module_function

    def parse(path)
      lines = File.readlines(path, encoding: "UTF-8")
      files = []
      current = nil
      fence = nil
      body = []

      flush = lambda do
        return unless current && fence
        files << [current, body.join]
        current = nil
        fence = nil
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

        if (match = line.match(/^## `(.+)`\s*$/))
          current = match[1]
          next
        end

        next unless current && (match = line.match(/^(`{3,})[A-Za-z0-9_-]*\s*$/))
        fence = match[1]
        body = []
      end

      raise "snapshot extract: unterminated block in #{path}" if current || fence

      files
    end

    def write(files, root)
      files.each do |relative, body|
        target = File.join(root, relative)
        FileUtils.mkdir_p(File.dirname(target))
        File.write(target, body, encoding: "UTF-8")
      end
      files.size
    end
  end
end

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: ruby snapshot_extract.rb [--to DIR] SNAPSHOT.md..."
  opts.on("--to DIR") { |dir| options[:root] = dir }
end.parse!(ARGV)

abort "snapshot extract: give at least one snapshot" if ARGV.empty?
root = File.expand_path(options.fetch(:root, Dir.mktmpdir("master-snapshot-")))
FileUtils.mkdir_p(root)

count = ARGV.sum do |path|
  Operator::SnapshotExtract.write(Operator::SnapshotExtract.parse(path), root)
end

puts "snapshot0: rehydrated #{count} text file(s) into #{root}"
