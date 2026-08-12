# frozen_string_literal: true

# No two files that can be loaded together define the same top-level constant.
#
# `already initialized constant ROOT` in bin/check's output looked cosmetic. It
# was the only thing standing between the security sweep and scanning a music
# directory: `rake test` requires MASTER/tools/security_sweep.rb and loads
# STUDIO/dilla/dilla.rb, both defined a bare top-level ROOT pointing at different
# trees, and Ruby resolves that by warning and letting the SECOND assignment win.
# Load order decided whether `git ls-files` ran against pub4 or against
# STUDIO/dilla, and the sweep printed "0 tracked secrets" either way.
#
# 24 files still define a bare top-level ROOT and that is fine: a standalone
# script run as `ruby thing.rb` never shares an interpreter with another. What is
# not fine is two such files both being *requirable*, which is the set this
# checks — every file reached by a `require_relative` anywhere in the repo.
#
# Known limitation, stated rather than hidden: only `require_relative` is
# followed. A plain `require` resolves against $LOAD_PATH, which depends on how
# the process was started, so following it would mean guessing. Zeitwerk-autoloaded
# files under MASTER/lib are namespaced and do not define top-level constants.
#
#   ruby MASTER/tools/constant_collisions.rb
#   ruby MASTER/tools/constant_collisions.rb --json
#
# Wired as `rake lint:constant_collisions`, pinned by test/test_constant_collisions.rb.

require "json"

module Pub4
  class ConstantCollisions
    ROOT = File.expand_path("../..", __dir__)
    TREES = %w[MASTER OPENBSD RAILS STUDIO].freeze
    SKIP = %r{/(vendor|node_modules|tmp|log|knowledge|output|\.master|\.git)/}

    # A constant assigned at column zero. Indented ones are inside a module or
    # class and namespaced by it.
    TOP_LEVEL = /\A([A-Z][A-Za-z0-9_]*)\s*=[^=~]/
    REQUIRE_RELATIVE = /require_relative\s+["']([^"']+)["']/

    def self.files
      @files ||= TREES.flat_map { |tree| Dir.glob(File.join(ROOT, tree, "**", "*.rb")) }
                      .reject { |path| path =~ SKIP }
                      .sort
    end

    def self.read(path)
      File.read(path)
    rescue StandardError
      ""
    end

    # Every file some other file pulls into its process.
    def self.requirable
      @requirable ||= begin
        found = {}
        files.each do |path|
          read(path).scan(REQUIRE_RELATIVE).flatten.each do |target|
            resolved = File.expand_path(target, File.dirname(path))
            found[resolved.end_with?(".rb") ? resolved : "#{resolved}.rb"] = true
          end
        end
        found
      end
    end

    # constant => the requirable files that define it at the top level.
    def self.definitions(paths = files.select { |path| requirable[path] })
      paths.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |path, found|
        read(path).each_line do |line|
          found[Regexp.last_match(1)] << path.sub("#{ROOT}/", "") if line =~ TOP_LEVEL
        end
      end
    end

    def self.run
      loadable = files.select { |path| requirable[path] }
      findings = definitions(loadable).filter_map do |name, paths|
        next if paths.uniq.size < 2

        { "constant" => name, "files" => paths.uniq }
      end

      { "scanned" => files.size, "requirable" => loadable.size, "findings" => findings }
    end
  end
end

if $PROGRAM_NAME == __FILE__
  report = Pub4::ConstantCollisions.run

  if ARGV.include?("--json")
    puts JSON.pretty_generate(report)
  else
    report["findings"].each do |row|
      puts "#{row['constant']} is defined at the top level of #{row['files'].size} requirable files:"
      row["files"].each { |file| puts "  #{file}" }
    end
    puts
    puts "#{report['requirable']} requirable of #{report['scanned']} first-party Ruby files"
    puts "constant_collisions: #{report['findings'].empty? ? 'clean' : "#{report['findings'].size} collision(s)"}"
  end

  exit(report["findings"].empty? ? 0 : 1)
end
