# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require File.expand_path("../lib/fix/scale_snap", __dir__)

# A synthetic stylesheet exercises each rule the pass keeps: what it snaps,
# what it leaves, and that apply goes through the guard and the re-render hook.
class ScaleSnapTest < Minitest::Test
  Snap = Master::Fix::ScaleSnap
  SHEET = <<~CSS
    .card {
      padding: 7px 16px;
      margin-top: 5px;
      gap: 0.52rem;
      font-size: 15px;
      border-radius: 11px;
      color: #123456;
      font-family: Arial;
      width: 13px;
      margin-bottom: calc(7px + 1vw);
      padding-left: 7px; // scale: ok
      margin-left: -7px;
    }
    @media (min-width: 600px) {
      .card { margin: 0; }
      .card {
        padding: 7px;
      }
    }
    .on { padding: 8px; }
  CSS

  def setup
    @root = Dir.mktmpdir("snap")
    FileUtils.mkdir_p(File.join(@root, "RAILS/__shared/app/assets/stylesheets"))
    FileUtils.mkdir_p(File.join(@root, "RAILS/brgen/app/assets/stylesheets"))
    File.write(File.join(@root, "RAILS/__shared/design_tokens.yml"),
               YAML.dump("scale" => { "space_px" => [0, 4, 8, 16, 24], "radius_px" => [0, 4, 8, 12] },
                         "shared_chrome" => { "font_size_body" => "1rem", "font_size_title" => "1.25rem" }))
    File.write(File.join(@root, "RAILS/__shared/app/assets/stylesheets/_tokens.scss"),
               "  --space-1: 0.25rem;\n  --space-2: 0.5rem;\n  --text-sm: 0.875rem;\n  --text-base: 1rem;\n  --radius-md: 12px;\n")
    @sheet = File.join(@root, "RAILS/brgen/app/assets/stylesheets/card.scss")
    File.write(@sheet, SHEET)
    @tokens = Master::Fix::LayoutScoreTokens.load(@root)
  end

  def teardown = FileUtils.remove_entry(@root)

  def afters = Snap.propose(root: @root, files: [@sheet], tokens: @tokens).to_h { |f| [f[:line], f[:after].strip] }

  def test_snaps_spacing_to_the_nearest_token_and_names_it
    found = afters
    assert_equal "padding: var(--space-2, 8px) 16px;", found[2]
    assert_equal "margin-top: var(--space-1, 4px);", found[3]
  end

  def test_rem_stays_rem_and_uses_a_named_token
    assert_equal "gap: var(--space-2, 0.5rem);", afters[4]
  end

  def test_leaves_ties_colours_fonts_and_context_alone
    found = afters
    assert_nil found[5], "15px sits between 14 and 16"
    assert_equal "border-radius: var(--radius-md, 12px);", found[6]
    assert_nil found[7], "colour"
    assert_nil found[8], "font family"
    assert_nil found[9], "width is not a snapped property"
    assert_nil found[10], "calc() is context"
    assert_nil found[11], "scale: ok opts out"
    assert_nil found[20], "already on scale"
  end

  def test_negative_lengths_snap_by_magnitude_without_a_var
    assert_equal "margin-left: -8px;", afters[12]
  end

  def test_media_blocks_are_skipped_unless_asked
    assert_nil afters[17]
    with = Snap.propose(root: @root, files: [@sheet], tokens: @tokens, media: true).map { |f| f[:line] }
    assert_includes with, 17
  end

  def test_findings_are_advisory_scale_snap_with_exact_before_after
    f = Snap.propose(root: @root, files: [@sheet], tokens: @tokens).first
    assert_equal "SCALE_SNAP", f[:law]
    assert f[:advisory]
    assert_equal "  padding: 7px 16px;", f[:before]
    assert_equal "  padding: var(--space-2, 8px) 16px;", f[:after]
  end

  def test_report_is_a_dry_run_that_writes_only_the_report
    findings = Snap.propose(root: @root, files: [@sheet], tokens: @tokens)
    path = Snap.report(findings, root: @root)
    assert_equal SHEET, File.read(@sheet)
    assert_equal findings.size, JSON.parse(File.read(path))["count"]
    assert_equal File.join(@root, "MASTER/.master/scale_snap/report.json"), path
  end

  def test_apply_needs_a_rescore_hook
    findings = Snap.propose(root: @root, files: [@sheet], tokens: @tokens)
    assert_equal 0, Snap.apply(findings, root: @root)[:applied]
    assert_equal SHEET, File.read(@sheet)
  end

  def guard(blocked: false)
    verdict = Struct.new(:blocked?).new(blocked)
    Object.new.tap { |g| g.define_singleton_method(:verdict) { |**| verdict } }
  end

  def test_apply_keeps_the_rewrite_when_the_score_holds
    findings = Snap.propose(root: @root, files: [@sheet], tokens: @tokens)
    out = Snap.apply(findings, root: @root, rescore: ->(_) { true }, guard:)
    assert_equal 1, out[:applied]
    assert_includes File.read(@sheet), "padding: var(--space-2, 8px) 16px;"
  end

  def test_apply_rolls_back_when_the_score_drops
    findings = Snap.propose(root: @root, files: [@sheet], tokens: @tokens)
    out = Snap.apply(findings, root: @root, rescore: ->(_) { false }, guard:)
    assert_equal 1, out[:score_dropped]
    assert_equal SHEET, File.read(@sheet)
  end

  def test_apply_refuses_when_the_write_guard_blocks_and_skips_stale_lines
    findings = Snap.propose(root: @root, files: [@sheet], tokens: @tokens)
    assert_equal 1, Snap.apply(findings, root: @root, rescore: ->(_) { true }, guard: guard(blocked: true))[:guard_refused]
    File.write(@sheet, ".other { margin: 1px; }\n")
    assert Snap.apply(findings, root: @root, rescore: ->(_) { true }, guard:)[:stale].positive?
  end
end
