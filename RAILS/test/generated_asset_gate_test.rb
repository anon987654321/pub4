# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../../MASTER/gates/lib/source/generated_asset"

# The mtime/dirtiness check is green when a committed build disagrees with
# its sources: git checkout stamps both files together. This is the case
# that shipped bsdports application.css with --radius-card: 16px after the
# sources moved to 12px.
class GeneratedAssetGateTest < Minitest::Test
  def gate
    Deploy::GeneratedAssetGate.new
  end

  def check(source_css, build_css)
    Dir.mktmpdir do |dir|
      source = File.join(dir, "tokens.scss")
      build = File.join(dir, "application.css")
      File.write(source, source_css)
      File.write(build, build_css)
      result = Deploy::GateResult.new
      gate.send(:content_stale?, [ source ], build, result, "bsdports")
      result
    end
  end

  def test_a_literal_token_the_sources_do_not_declare_is_stale
    result = check("--radius-card: 12px;\n", "--radius-card: 16px;\n")

    refute result.ok?
    assert_match(/--radius-card: 16px/, result.failures.first)
  end

  def test_matching_literals_are_fresh
    result = check("--radius-card: 12px;\n", "--radius-card: 12px;\n")

    assert result.ok?, result.failures.join
  end

  def test_an_interpolated_color_matches_its_mixin_default
    source = <<~'SCSS'
      $bg: #17161c;
      --bg: #{$bg};
    SCSS
    result = check(source, "--bg: #17161c;\n")

    assert result.ok?, result.failures.join
  end

  # The measured case: marketplace spells --accent-ink: #fff, and every other
  # root interpolates it, so the build's #000000 and #110f19 are not drift.
  def test_a_token_also_set_by_interpolation_is_not_held_to_its_literals
    source = <<~'SCSS'
      :root { --accent-ink: #{$bg}; }
      body.vertical-marketplace { --accent-ink: #fff; }
    SCSS
    result = check(source, "--accent-ink: #000000;\n--accent-ink: #fff;\n")

    assert result.ok?, result.failures.join
  end

  def compile_check(build_css)
    Dir.mktmpdir do |dir|
      build = File.join(dir, "application.css")
      File.write(build, build_css)
      result = Deploy::GateResult.new
      [gate.send(:failed_compile?, build, result, "amber"), result]
    end
  end

  # All three committed builds were this page for a day, with the gate green.
  def test_a_sass_error_page_is_a_failed_build
    flagged, result = compile_check(%(/* Error: expected "{".\n *    ,\n */\nbody::before { content: "Error"; }\n))

    assert flagged
    refute result.ok?
  end

  def test_a_compiled_stylesheet_is_not_an_error_page
    flagged, result = compile_check(":root{--bg: #000000}body{margin:0}\n/* Error: in a comment later */\n")

    refute flagged
    assert result.ok?, result.failures.join
  end

  def test_live_builds_match_their_source_literals
    result = Deploy::GeneratedAssetGate.run

    assert result.ok?, result.failures.join(", ")
  end
end
