# frozen_string_literal: true

require "minitest/autorun"
require "pathname"
require "tmpdir"
require_relative "gate_fixture"
require_relative "../../gates/lib/source/css_minify_integrity"

# Compile each app's entrypoint twice and compare.
#
# check_app joins its app name onto RAILS_ROOT, so a fixture reaches it as the
# relative path from there — no constant rewriting, and the gate resolves the
# stylesheet exactly the way it does for a real app.
#
# Two failures are planted. An entrypoint that does not compile ships no
# stylesheet at all, and the gate has to say which app rather than crash the
# run. The selector-loss half cannot be planted: it detects a dart-sass
# compressed-output bug, and the compiler installed here no longer has it, so
# nothing this test can write makes a selector disappear. What is provable about
# that half is the normalisation the comparison rests on, which is where its
# false positives came from.
class CssMinifyIntegrityGateTest < Minitest::Test
  include GateFixture

  GATE = Deploy::CssMinifyIntegrityGate

  # The gate requires the compiler inside #run and reports itself inconclusive
  # when it is absent, so a test reaching check_app has to load it first or
  # every compile reads as a failure.
  SASS = begin
    require "sass-embedded"
    true
  rescue LoadError
    false
  end

  def setup
    skip "sass-embedded unavailable — the gate reports itself inconclusive here" unless SASS
  end

  def check(scss)
    Dir.mktmpdir do |dir|
      plant(dir, "app/assets/stylesheets/application.scss", scss)
      rel = Pathname.new(dir).relative_path_from(Pathname.new(GATE::RAILS_ROOT)).to_s
      result = Deploy::GateResult.new
      GATE.new.send(:check_app, result, rel)
      result
    end
  end

  def test_an_entrypoint_that_does_not_compile_fails_and_names_the_app
    result = check(%(@use "no-such-partial";\n.a { color: red; }\n))

    refute result.ok?, "an entrypoint that cannot compile passed"
    assert_match(/failed to compile/, result.failures.first)
    assert_match(/Sass::CompileError/, result.failures.first)
  end

  def test_the_same_entrypoint_passes_once_it_compiles
    result = check(".a, .b, .c { color: red; }\n")

    assert result.ok?, result.failures.join(", ")
    assert_equal 1, result.checks_ran
  end

  # A long compound-selector list is the shape the gate was written for. Every
  # item survives compression here, which is the state of the compiler rather
  # than of the check.
  def test_a_long_compound_selector_list_survives_compression
    selectors = (1..30).map { |i| ".feed-card.listing-#{i} .feed-card-avatar" }
    result = check("#{selectors.join(",\n")} { width: 32px; }\n")

    assert result.ok?, result.failures.join(", ")
  end

  def test_a_missing_entrypoint_is_inconclusive_rather_than_clean
    result = Dir.mktmpdir do |dir|
      rel = Pathname.new(dir).relative_path_from(Pathname.new(GATE::RAILS_ROOT)).to_s
      r = Deploy::GateResult.new
      GATE.new.send(:check_app, r, rel)
      r
    end

    assert_equal :inconclusive, result.outcome
    assert_match(/no application\.scss/, result.unchecked.first)
  end

  # Compressed output strips the whitespace around an explicit combinator and
  # keeps the single space that IS the descendant combinator. Normalising by
  # deleting all whitespace made `.a>b c` match `.a>bc`, and reported every such
  # selector as lost.
  def test_normalisation_collapses_combinators_without_joining_words
    gate = GATE.new

    assert_equal gate.send(:normalize_selector, ".a>.b"), gate.send(:normalize_selector, ".a > .b")
    assert_equal gate.send(:normalize_selector, ".a+.b"), gate.send(:normalize_selector, ".a  +  .b")
    refute_equal gate.send(:normalize_selector, ".a .b"), gate.send(:normalize_selector, ".a.b")
  end
end
