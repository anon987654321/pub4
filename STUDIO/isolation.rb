# frozen_string_literal: true

require "open3"
require "rbconfig"

# Which tests only pass because of the company they keep, and which only fail.
#
# dilla's files deliberately share one process — the engine takes half a second
# to load and there is nothing for six files to collide over — so every test in
# that suite can see what the ones before it left behind. Three defects this
# session had exactly that shape and each was invisible from a normal run:
#
#   provenance recorded DILLA_QUIET, DILLA_ASSET_CHECK and DILLA_KNOB_CHECK as
#   operator pins. The suite sets all three to keep itself quiet, Open3 merges
#   the parent environment into the child, and the manifest wrote the harness's
#   plumbing down as the operator's choices. Passed alone, failed in the suite.
#
#   the frozen test compares File.mtime on project/session.json, which other
#   probes in the same suite write. Fails intermittently in the suite, never
#   alone.
#
#   a stale renderer count passed alone and failed once the file it counted grew.
#
# All three were found by running one test on its own after a hunch. This does
# it for all of them, which is the difference between noticing and checking.
#
# The two directions are not the same defect and are reported separately:
#
#   suite-only failure   the test is right and something before it interferes
#   isolation-only failure   the test needs setup a neighbour happens to do,
#                            so it is asserting less than it claims
class StudioIsolation
  ROOT = File.expand_path(__dir__)
  RUBY = RbConfig.ruby

  Outcome = Struct.new(:name, :file, :alone, :suite, keyword_init: true)

  def self.run(pattern: nil, io: $stdout)
    new(pattern: pattern, io: io).run
  end

  def initialize(pattern: nil, io: $stdout)
    @pattern = pattern
    @io = io
  end

  def files = Dir.glob(File.join(ROOT, "test", "test_dilla_*.rb")).sort

  # Parsed out of the source rather than asked of Minitest, so this needs no
  # cooperation from the suite and cannot be defeated by a runner that dies
  # partway.
  def test_names(file)
    File.read(file).scan(/^\s*def (test_\w+)/).flatten +
      File.read(file).scan(/^\s*test\s+["']([^"']+)["']/).flatten.map { |n| "test_#{n.gsub(/\W+/, '_')}" }
  end

  def run
    rounds = suite_rounds
    suite_failures = rounds.flatten.uniq
    intermittent = suite_failures.reject { |name| rounds.all? { |r| r.include?(name) } }
    @io.puts "isolation: suite reports #{suite_failures.length} failing test(s) across #{ENV.fetch(%q(SUITE_ROUNDS), %q(3))} round(s)"

    names = files.flat_map { |f| test_names(f).map { |n| [ n, f ] } }
    names = names.select { |n, _| n.include?(@pattern) } if @pattern
    @io.puts "isolation: running #{names.length} test(s) one process each — this is slow on purpose"

    outcomes = names.map do |name, file|
      alone = passes_alone?(file, name)
      Outcome.new(name: name, file: file, alone: alone, suite: !suite_failures.include?(name))
    end

    report(outcomes, intermittent, rounds.length)
  end

  private

  def passes_alone?(file, name)
    _out, status = Open3.capture2e(RUBY, "-I#{File.join(ROOT, 'test')}", file, "-n", name,
                                   chdir: ROOT)
    status.success?
  end

  # Per round, so a test that fails in some rounds and not others is named as
  # what it is. That is the most useful signal here and the one a single run
  # cannot produce: the frozen test races another probe over
  # project/session.json and fires perhaps one run in three, which reads as an
  # unlucky red rather than a defect until you see it is not every time.
  def suite_rounds
    rounds = Integer(ENV.fetch("SUITE_ROUNDS", "3"))
    rounds.times.map do
      out, _status = Open3.capture2e(RUBY, "-I#{File.join(ROOT, 'test')}",
                                     "-e", files.map { |f| "require #{f.dump}" }.join("\n"),
                                     chdir: ROOT)
      out.scan(/^\s*\w+#(test_\w+)/).flatten.uniq
    end
  end

  def report(outcomes, intermittent, rounds)
    if intermittent.any?
      @io.puts "isolation: fails in some suite rounds and not others — a race, not an unlucky red"
      intermittent.each { |name| @io.puts "  #{name}" }
    end
    suite_only = outcomes.select { |o| o.alone && !o.suite }
    alone_only = outcomes.select { |o| !o.alone && o.suite }

    if suite_only.any?
      @io.puts "isolation: passes alone, fails in the suite — something before it interferes"
      suite_only.each { |o| @io.puts "  #{o.name}" }
    end
    if alone_only.any?
      @io.puts "isolation: fails alone, passes in the suite — it depends on a neighbour's setup,"
      @io.puts "isolation: so it is asserting less than its name claims"
      alone_only.each { |o| @io.puts "  #{o.name}" }
    end
    if suite_only.empty? && alone_only.empty? && intermittent.empty?
      @io.puts "isolation: every test agrees with itself alone, in company, and across #{rounds} rounds"
      return 0
    end
    suite_only.length + alone_only.length + intermittent.length
  end
end
