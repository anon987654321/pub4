# frozen_string_literal: true

require "minitest/autorun"
require "prism"
require "tmpdir"

# `rb_long_method` has been on the backlog since it was first measured, and the
# reason it never converged is that nothing held the line while it was being
# worked. The count was 81, then 29 after a re-measure, and 55 when picked up
# again on 2026-08-10 — and one of the 55 was a method written earlier the same
# day, by the agent closing the backlog. A finding list is a snapshot; it cannot
# stop the number rising while you shorten the entries on it.
#
# So this is a ratchet, on the same contract as coverage_ratchet_test.rb and
# MASTER's rake lint:spine: the ceilings below may fall and may never rise. It
# does not make anyone split a method. It makes the number visible, and it fails
# when someone adds a long one — including when that someone is an agent midway
# through fixing long methods.
#
# Counted in *code* lines — non-blank, non-comment, inside the body — not the raw
# span. MASTER's SMALL_FUNCTIONS rule made the same choice for the same reason:
# this tree's convention is a paragraph of rationale above the tricky line, and a
# span-based limit charges you for writing it. `stale?` in gates/lib/
# generated_asset.rb is 25 code lines inside a 47-line span; the only way to
# satisfy a span limit there is to delete the explanation.
class MethodLengthRatchetTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  LIMIT = 30

  ROOTS = %w[shared brgen amber bsdports gates tools test lib].freeze

  AREAS = {
    "gates" => %w[gates tools],
    "shared" => %w[shared],
    "brgen" => %w[brgen],
    "amber" => %w[amber],
    "bsdports" => %w[bsdports],
    "test" => %w[test lib],
  }.freeze

  # area => [methods over LIMIT, longest method in code lines]
  #
  # Measured 2026-08-10, after splitting page_inventory's
  # brgen_route_by_convention (75 -> 24, behaviour proved identical over 585
  # route inputs) and deploy_backlog_test's 102-line bundle of six unrelated
  # contracts. Lower a number when you split something; never raise one.
  #
  # gates is by far the worst and that is the honest shape of it: these are
  # audit routines that walk a tree and accumulate findings, and several want
  # the same treatment production.rb's check_app got — split at the
  # responsibility bound, then mutation-test each half.
  CEILINGS = {
    "gates" => [39, 68],
    # 57 -> 48 on 2026-08-23. record_public_href was the 52: one case statement
    # over every routable class in the city, split into the apex, the verticals
    # and the two media engines. A sentinel separates "no branch claimed this
    # class" from "the branch claimed it and there is no link", because only the
    # first may fall through to polymorphic_path and both are nil.
    "brgen" => [9, 48],
# 3/34 -> 2/32 on 2026-08-25. The 48 was css_coverage_lint's used_names:
# five copies of the same three lines, one per way of applying a class,
# which is why it grew past this ratchet on every new way found. Split
# into four extractors and one recorder, with each reason kept next to
# its own pattern. css_coverage_lint_test passes on the same baselines,
# so the counts it reports are unchanged.
"shared" => [2, 32],
    "amber" => [1, 35],
    "bsdports" => [1, 46],
  }.freeze

  def ruby_files
    @ruby_files ||= ROOTS.flat_map { |r| Dir.glob(File.join(ROOT, r, "**/*.rb")) }
                         .reject { |f| f.match?(%r{/(vendor|node_modules|public)/|/db/migrate/}) }
                         .sort
  end

  def area_for(path)
    top = path.delete_prefix("#{ROOT}/").split("/").first
    AREAS.find { |_, roots| roots.include?(top) }&.first
  end

  # [code_lines, name] for every method in the file, using Prism rather than a
  # `def`/`end` regex — nested defs, one-line defs and heredocs all break the
  # regex version, and this file's whole job is to be trusted about a number.
  def methods_in(path)
    src = File.read(path)
    parsed = Prism.parse(src)
    return [] unless parsed.success?

    lines = src.lines
    found = []
    visit = lambda do |node|
      if node.is_a?(Prism::DefNode) && node.body
        span = (node.body.location.start_line..node.body.location.end_line)
        code = span.count do |n|
          stripped = lines[n - 1].to_s.strip
          !stripped.empty? && !stripped.start_with?("#")
        end
        found << [code, node.name]
      end
      node.compact_child_nodes.each { |child| visit.call(child) }
    end
    visit.call(parsed.value)
    found
  end

  def measure
    counts = Hash.new(0)
    worst = Hash.new(0)
    longest = {}

    ruby_files.each do |path|
      area = area_for(path)
      next unless area

      methods_in(path).each do |code, name|
        next unless code > LIMIT

        counts[area] += 1
        next unless code > worst[area]

        worst[area] = code
        longest[area] = "#{path.delete_prefix("#{ROOT}/")} #{name} (#{code} lines)"
      end
    end

    [counts, worst, longest]
  end

  def test_the_scan_reaches_the_tree_it_claims_to
    refute_empty ruby_files, "no ruby files found — the glob is wrong, not the tree"
    assert ruby_files.any? { |f| f.include?("/engines/") },
           "engine code is missing, the blind spot that hid 57 views when the verticals moved"
  end

  def test_method_length_is_measured_in_code_lines_not_span
    Dir.mktmpdir do |dir|
      path = File.join(dir, "probe.rb")
      body = (["    # explanation"] * 40 + ["    x = 1"] * 3).join("\n")
      File.write(path, "def documented\n#{body}\nend\n")
      code, name = methods_in(path).first
      assert_equal :documented, name
      assert_equal 3, code, "40 comment lines must not count against a 3-line method"
    end
  end

  def test_no_area_exceeds_its_ceiling
    counts, worst, longest = measure
    risen = []

    CEILINGS.each do |area, (max_count, max_lines)|
      if counts[area] > max_count
        risen << "#{area}: #{counts[area]} methods over #{LIMIT} lines, ceiling is #{max_count}"
      end
      next unless worst[area] > max_lines

      risen << "#{area}: longest is now #{worst[area]} lines, ceiling is #{max_lines} — #{longest[area]}"
    end

    unknown = counts.keys - CEILINGS.keys
    unknown.each { |area| risen << "#{area}: #{counts[area]} over the limit and no ceiling declared" }

    assert_empty risen, <<~MSG.strip
      long methods have increased:

        #{risen.join("\n  ")}

      Split the method rather than raising the ceiling. If a split is genuinely
      wrong here, say why in CEILINGS and move the number — but the number only
      moves down without an argument.
    MSG
  end

  def test_ceilings_are_not_slack
    counts, worst, = measure
    slack = CEILINGS.filter_map do |area, (max_count, max_lines)|
      next if counts[area] == max_count && worst[area] == max_lines

      "#{area}: now #{counts[area]}/#{worst[area]}, recorded #{max_count}/#{max_lines}"
    end

    assert_empty slack, <<~MSG.strip
      the tree is better than the ratchet records — lower these:

        #{slack.join("\n  ")}

      A ceiling left above the real number is slack the next long method can grow
      into without failing anything, which is how this backlog item survived
      three separate measurements.
    MSG
  end
end
