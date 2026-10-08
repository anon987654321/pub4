# frozen_string_literal: true

require "minitest/autorun"
require "pathname"
require "tmpdir"
require_relative "gate_fixture"
require_relative "../../../MASTER/gates/lib/source/css_minify_integrity"

# Compile each app's entrypoint twice and compare.
#
# check_app joins its app name onto RAILS_ROOT, so a fixture reaches it as the
# relative path from there — no constant rewriting, and the gate resolves the
# stylesheet exactly the way it does for a real app.
#
# Two failures are planted. An entrypoint that does not compile ships no
# stylesheet at all, and the gate has to say which app rather than crash the
# run. The selector-loss half detects a dart-sass compressed-output bug the
# installed compiler no longer has, so no SCSS makes a selector disappear; the
# loss is planted in the compiler's output instead, which proves the comparison
# and not the compiler. The normalisation it rests on is tested too, because
# that is where its false positives came from.
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

  # The compiler cannot be made to lose a selector, but the comparison can be
  # handed compressed output that has lost one. This is the shape seen live:
  # the listing qualifier gone, leaving the bare avatar selector.
  def test_a_selector_that_loses_its_qualifier_under_compression_fails
    scss = ".feed-card.listing .feed-card-avatar, .post-card .avatar, .story .avatar { width: 32px; }\n"
    real = Sass.method(:compile)
    lossy = lambda do |entry, **options|
      css = real.call(entry, **options).css
      css = css.sub(".feed-card.listing .feed-card-avatar", ".feed-card-avatar") if options[:style] == :compressed
      Struct.new(:css).new(css)
    end

    result = with_compile(lossy) { check(scss) }

    refute result.ok?, "a selector that lost its qualifier passed"
    assert_match(/lost selector\(s\) under compression/, result.failures.first)
    assert_match(/missing after compression: \[".feed-card.listing .feed-card-avatar"\]/, result.failures.first)
  end

  def with_compile(impl)
    Sass.singleton_class.send(:alias_method, :__real_compile, :compile)
    Sass.define_singleton_method(:compile, &impl)
    yield
  ensure
    Sass.singleton_class.send(:alias_method, :compile, :__real_compile)
    Sass.singleton_class.send(:remove_method, :__real_compile)
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
