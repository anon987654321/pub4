# frozen_string_literal: true

# No first-party Ruby tree is silently outside MASTER's own law.
#
# A gate whose scope is a path literal loses coverage without failing. `core/`
# lived outside the scanned `lib/` for three weeks and the gates stayed green;
# the engines migration made four scanners stop seeing 57 views and the falling
# lint baseline read as improvement. Shrinking looks like winning.
#
# So this reports what was COVERED, not only what failed, and refuses a
# directory that is in neither list. See data/scan_coverage.yml.
#
#   ruby MASTER/tools/scan_coverage.rb
#   ruby MASTER/tools/scan_coverage.rb --json
#
# Wired as `rake lint:scan_coverage` and pinned by MASTER/test/test_scan_coverage.rb.

require "json"
require "yaml"

module Pub4
  class ScanCoverage
    MASTER = File.expand_path("..", __dir__)
    MANIFEST = File.join(MASTER, "data", "scan_coverage.yml")

    # Directories that are not MASTER's own source: dependencies, generated
    # output, and the two gitignored trees. Absent from both lists by nature, so
    # demanding an exemption for them would be noise.
    NOT_SOURCE = %w[
      vendor node_modules tmp log knowledge output .master .git reports coverage
    ].freeze

    def self.manifest
      @manifest ||= YAML.safe_load_file(MANIFEST).fetch("scan_coverage")
    end

    # Top-level directories of MASTER that contain Ruby at any depth.
    def self.ruby_dirs
      @ruby_dirs ||= Dir.children(MASTER).select { |child| ruby_dir?(child) }.sort
    end

    def self.ruby_dir?(child)
      path = File.join(MASTER, child)
      return false unless File.directory?(path) && !File.symlink?(path)
      return false if NOT_SOURCE.include?(child)

      ruby_count(child).positive?
    end

    # Counted here as well as checked, because the count is the half that makes a
    # silent shrink visible.
    def self.ruby_count(dir)
      @counts ||= {}
      @counts[dir] ||= ruby_files(dir).size
    end

    # Ruby is what a Ruby interpreter runs, not what ends in .rb.
    #
    # This globbed "**/*.rb" alone, and every executable in bin/ is extensionless
    # by convention -- so bin/ counted zero Ruby files, failed ruby_dir?, never
    # entered ruby_dirs, and could not be reported as unclassified. The directory
    # holding gate, check, pub4 and master was in neither list, and the one file
    # whose job is to say so could not see it.
    def self.ruby_files(dir)
      Dir.glob(File.join(MASTER, dir, "**", "*")).select do |path|
        next false unless File.file?(path) && !File.symlink?(path)
        next false unless NOT_SOURCE.none? { |skip| path.include?("/#{skip}/") }

        File.extname(path) == ".rb" || ruby_shebang?(path)
      end
    end

    # One line, not the file. A shebang is the first line or it is absent.
    def self.ruby_shebang?(path)
      first = File.open(path, "rb") { |io| io.readline(chomp: true) }
      first.start_with?("#!") && first.include?("ruby")
    rescue EOFError, ArgumentError, Errno::EACCES, Errno::ENOENT
      false
    end

    def self.run
      roots = Array(manifest["roots"])
      exempt = manifest["exempt"] || {}
      findings = []

      (ruby_dirs - roots - exempt.keys).each do |dir|
        findings << { "kind" => "unclassified", "dir" => dir, "files" => ruby_count(dir),
                      "message" => "holds #{ruby_count(dir)} Ruby file(s) and is in neither " \
                                   "scan_coverage.roots nor scan_coverage.exempt" }
      end

      roots.each do |dir|
        next if ruby_dirs.include?(dir)

        findings << { "kind" => "empty_root", "dir" => dir, "files" => 0,
                      "message" => "listed as scanned but holds no Ruby — the gates that " \
                                   "read this root are measuring nothing" }
      end

      exempt.each do |dir, reason|
        unless File.directory?(File.join(MASTER, dir))
          findings << { "kind" => "stale_exemption", "dir" => dir, "files" => 0,
                        "message" => "exempt from the scan but no longer exists — an " \
                                     "exemption outliving its subject is a hole in a gate " \
                                     "nobody can see (soul.yml EXEMPTIONS_EXPIRE)" }
          next
        end

        next unless reason.to_s.strip.empty?

        findings << { "kind" => "unreasoned_exemption", "dir" => dir, "files" => ruby_count(dir),
                      "message" => "exempt with no reason written down — the reason is the " \
                                   "part that rots, so it is the part that must be recorded" }
      end

      { "covered" => roots.to_h { |dir| [dir, ruby_count(dir)] },
        "exempt" => exempt.keys.to_h { |dir| [dir, ruby_count(dir)] },
        "findings" => findings }
    end
  end
end

if $PROGRAM_NAME == __FILE__
  report = Pub4::ScanCoverage.run

  if ARGV.include?("--json")
    puts JSON.pretty_generate(report)
  else
    report["findings"].each { |row| puts "#{row['kind']}: #{row['dir']} — #{row['message']}" }
    puts
    covered = report["covered"]
    exempt = report["exempt"]
    puts "scanned:  #{covered.map { |dir, n| "#{dir} (#{n})" }.join(', ')} = #{covered.values.sum} files"
    puts "exempt:   #{exempt.map { |dir, n| "#{dir} (#{n})" }.join(', ')} = #{exempt.values.sum} files"
    puts "scan_coverage: #{report['findings'].empty? ? 'clean' : "#{report['findings'].size} finding(s)"}"
  end

  exit(report["findings"].empty? ? 0 : 1)
end
