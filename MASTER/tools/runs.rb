# frozen_string_literal: true

# Which entrypoint runs a given file, and which files nothing runs.
#
# "Does anything read this?" is the question that takes an afternoon in this
# repo and should take a second. amber's architecture record was deleted and
# nothing noticed because nothing read it; four RAILS scanners stopped seeing 57
# views when the verticals moved to engines, and the falling finding count read
# as improvement. Both are the same question, unasked.
#
#   ruby MASTER/tools/runs.rb                 # coverage summary + orphans
#   ruby MASTER/tools/runs.rb --who <path>    # which entrypoints reach a file
#   ruby MASTER/tools/runs.rb --json
#
# Reachability is computed, not declared: the globs come out of the runner files
# themselves, so a glob that changes in the Rakefile changes the answer here
# without anyone updating a list. The only declared part is CONVENTIONS, for
# runners whose glob lives inside a framework rather than in this repo.

require "json"

module Pub4
  class Runs
    ROOT = File.expand_path("../..", __dir__)

    # Files that orchestrate other files. Each is read for glob literals.
    RUNNERS = %w[
      MASTER/Rakefile
      STUDIO/Rakefile
      MASTER/bin/check
      MASTER/bin/ci
      MASTER/bin/gate
      MASTER/web/bin/ci
      OPENBSD/bin/check
      OPENBSD/bin/check-full
      OPENBSD/bin/check-rails
      OPENBSD/bin/check-openbsd
      OPENBSD/bin/check-vps
      RAILS/gates/runner.rb
      RAILS/gates/release.rb
      package.json
    ].freeze

    # `rails test` globs inside the framework, not in any file here. An app's
    # bin/ci reaching its own test tree is a convention, so it is written down
    # rather than inferred -- and named as an assumption, because an assumption
    # that looks like a measurement is how a gate ends up measuring nothing.
    CONVENTIONS = {
      "RAILS/amber/bin/ci" => ["RAILS/amber/test/**/*_test.rb"],
      "RAILS/brgen/bin/ci" => ["RAILS/brgen/test/**/*_test.rb", "RAILS/brgen/engines/*/test/**/*_test.rb"],
      "RAILS/bsdports/bin/ci" => ["RAILS/bsdports/test/**/*_test.rb"],
      "RAILS/shared/bin/ci" => ["RAILS/shared/test/**/*_test.rb"],
      "MASTER/web/bin/ci" => ["MASTER/web/test/**/*_test.rb"],
    }.freeze

    # Support files named like tests. A runner loads these; nothing runs them.
    HELPERS = %w[test_helper.rb test_defaults.rb test_support.rb].freeze

    # A string literal that looks like it selects ruby files.
    GLOB = /["']([A-Za-z0-9_.\-\/*\[\]{}]*\*[A-Za-z0-9_.\-\/*\[\]{}]*\.rb)["']/

    # A runner naming one file outright runs it just as surely. STUDIO's Rakefile
    # lists test_studio_gate.rb by name — deliberately, its comment says, because
    # the glob beside it would pull in the dilla and tool suites — and a
    # glob-only extractor read that as a test nothing runs. A path literal that
    # matches no test file matches nothing here, so this cannot invent coverage.
    EXACT = %r{["']((?:[A-Za-z0-9_.\-]+/)*(?:test|spec)/[A-Za-z0-9_.\-]+\.rb)["']}

    def self.globs
      @globs ||= begin
        found = Hash.new { |hash, key| hash[key] = [] }

        RUNNERS.each do |runner|
          path = File.join(ROOT, runner)
          next unless File.file?(path)

          base = runner.split("/").first
          source = File.read(path)
          (source.scan(GLOB).flatten + source.scan(EXACT).flatten).uniq.each do |glob|
            # Globs are written relative to the tree the runner lives in.
            found[runner] << (glob.start_with?("MASTER/", "RAILS/", "OPENBSD/", "STUDIO/") ? glob : "#{base}/#{glob}")
          end
        end

        CONVENTIONS.each { |runner, list| found[runner].concat(list) }
        found
      end
    end

    # A test is a file under a test/ or spec/ directory, not every file whose
    # name reads like one. The name alone was the first instrument and it was
    # wrong in both directions: law/ rules are named for what they detect, so
    # squint_test.rb read as a test (exempted by hand), MASTER/tools/test_naming.rb
    # is the lint over test names and read as an orphan test forever, and
    # lib/review/scan/self_test.rb read as a test that happened to be covered by
    # a bin/check glob — a false positive masked by a coincidence, which is the
    # worse half. Three files, all of them source. Adding a third exemption by
    # hand was the move this replaces, because the exemptions were describing a
    # rule the directory already states.
    #
    # 726 of the 729 files named like tests are under test/ or spec/; the three
    # that are not are those three. HELPERS stays: test_helper.rb IS under test/,
    # and a runner loads it rather than running it.
    TEST_DIR = %r{(\A|/)(test|spec)/}

    def self.test_files
      @test_files ||= Dir[File.join(ROOT, "{MASTER,RAILS,OPENBSD,STUDIO}/**/*.rb")]
                      .map { |path| path.sub("#{ROOT}/", "") }
                      .reject { |path| path =~ %r{/(node_modules|vendor|tmp|\.master|knowledge|output)/} }
                      .select { |path| path =~ TEST_DIR }
                      .select { |path| File.basename(path) =~ /\Atest_.*\.rb\z|_test\.rb\z|_spec\.rb\z/ }
                      .reject { |path| HELPERS.include?(File.basename(path)) }
                      .sort
    end

    def self.who_runs(file)
      globs.select { |_, list| list.any? { |glob| File.fnmatch?(glob, file, File::FNM_PATHNAME | File::FNM_EXTGLOB) } }
           .keys
    end

    def self.run
      reached = {}
      test_files.each { |file| reached[file] = who_runs(file) }
      orphans = reached.select { |_, runners| runners.empty? }.keys

      {
        tests: reached.size,
        reached: reached.size - orphans.size,
        orphans: orphans,
        runners: globs.transform_values(&:sort),
      }
    end
  end
end

if $PROGRAM_NAME == __FILE__
  if (index = ARGV.index("--who"))
    target = ARGV[index + 1] or abort "usage: runs.rb --who <path>"
    runners = Pub4::Runs.who_runs(target)
    puts runners.empty? ? "nothing runs #{target}" : runners.join("\n")
    exit(runners.empty? ? 1 : 0)
  end

  report = Pub4::Runs.run

  if ARGV.include?("--json")
    puts JSON.pretty_generate(report)
  else
    puts "#{report[:reached]}/#{report[:tests]} test files reachable from an entrypoint"
    unless report[:orphans].empty?
      puts
      puts "nothing runs these:"
      report[:orphans].each { |file| puts "  #{file}" }
    end
  end

  exit(report[:orphans].empty? ? 0 : 1)
end
