# frozen_string_literal: true

# No two files that can be loaded together define the same top-level constant.
#
# Historically, MASTER/tools/security_sweep.rb and MASTER/tools/dilla/dilla.rb
# both defined a top-level ROOT, so whichever loaded last silently changed the
# repository scope used by the security scan. The old MASTER/tools/dilla path is
# gone; security_sweep now owns the explicit SWEEP_ROOT name. Keep this detector
# and its regression test so a broad top-level constant cannot silently return.
#
# 24 files still define a bare top-level ROOT and that is fine: a standalone
# script run as `ruby thing.rb` never shares an interpreter with another. What is
# not fine is two such files both being *requirable*, which is the set this
# checks — every file reached by `require_relative` in MASTER, OPENBSD and RAILS.
# STUDIO tool suites intentionally run in separate processes and have their own
# per-subject isolation gate because their current top-level API is not namespaced.
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

module Operator
  class ConstantCollisions
    ROOT = File.expand_path("../..", __dir__)
    TREES = %w[MASTER OPENBSD RAILS].freeze
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
  report = Operator::ConstantCollisions.run

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
