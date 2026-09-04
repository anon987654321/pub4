# frozen_string_literal: true

require "minitest/autorun"
require_relative "../shared/lib/pub4/scale_lint"

# The rhythm axis, ratcheted.
#
# BreakpointLint's header lists colour, space, motion and elevation as
# single-sourced. Colour, motion and elevation are. Space is single-sourced as a
# *token set* and by nothing that checks the sheets obey it, which is the same
# gap breakpoints had before that lint existed -- and it measured the same way:
# 88 spacing literals off the 4px grid, 13 line-heights around one body rhythm.
#
# What this is not: a test that anything looks good. It asserts that the numbers
# in the stylesheets come from a declared set, which is the only part of "well
# proportioned" a source-level check can honestly claim. The declared set lives
# in design_tokens.yml `scale:` and the values are unchanged by this file --
# nothing here moves a pixel.
class ScaleLintTest < Minitest::Test
  LINT = Pub4::ScaleLint
  TOKENS_SCSS = File.expand_path("../shared/app/assets/stylesheets/_tokens.scss", __dir__)

  def counts = @counts ||= LINT.counts

  def findings_for(kind) = LINT.findings.select { |f| f.kind == kind }

  def test_no_kind_exceeds_its_baseline_on_either_surface
    regressions = LINT::SURFACES.flat_map do |surface|
      found = LINT.counts_for(surface)
      LINT.baselines_for(surface).filter_map do |kind, baseline|
        count = found.fetch(kind, 0)
        next if count <= baseline

        examples = LINT.findings_for(surface).select { |f| f.kind == kind }.first(6).map do |f|
          near = LINT.nearest(f)
          "#{f.file}:#{f.line} #{f.property}: #{f.value}#{near ? " (nearest step #{near})" : ""}"
        end
        "#{surface}/#{kind}: #{count}, baseline #{baseline}\n    #{examples.join("\n    ")}"
      end
    end

    assert_empty regressions, "a value off the declared scale:\n  #{regressions.join("\n  ")}"
  end

  # A baseline that has been beaten and never lowered is a baseline nobody
  # trusts -- the same contract breakpoint_lint holds itself to.
  def test_baselines_are_not_stale
    stale = LINT::SURFACES.flat_map do |surface|
      found = LINT.counts_for(surface)
      LINT.baselines_for(surface).filter_map do |kind, baseline|
        count = found.fetch(kind, 0)
        "#{surface}/#{kind}: #{count} found, baseline still #{baseline}" if count < baseline
      end
    end

    assert_empty stale, "lower these in design_tokens.yml scale.baselines:\n  #{stale.join("\n  ")}"
  end

  def test_every_kind_the_lint_can_report_has_a_baseline_on_every_surface
    LINT::SURFACES.each do |surface|
      unbaselined = LINT.counts_for(surface).keys - LINT.baselines_for(surface).keys
      assert_empty unbaselined, "#{surface}: counted and bounded by nothing: #{unbaselined.inspect}"
    end
  end

  def test_the_two_surfaces_declare_the_same_kinds
    apps, face = LINT::SURFACES.map { |surface| LINT.baselines_for(surface).keys.sort }

    assert_equal apps, face,
                 "one surface is exempt from a kind the other is measured on, which is how they diverge"
  end

  # --- one scale, two surfaces --------------------------------------------

  # The reason the face is in the corpus at all. MASTER's web face and the three
  # Rails apps are one family: design_tokens.yml already generates the face's
  # :root, so the colours and the motion curves are shared. The rhythm was not,
  # and a control in the face sitting 2px off the same control in brgen is the
  # visible half of that.
  def test_the_face_is_measured_against_the_same_scale_as_the_apps
    refute_empty LINT.face_stylesheets, "face.css is not in the corpus, so the face is measured by nothing"
    assert LINT.face_stylesheets.any? { |path| path.end_with?("face.css") }

    assert_operator LINT.app_stylesheets.size, :>, 50
    assert_empty LINT.app_stylesheets & LINT.face_stylesheets, "a sheet is counted on both surfaces"
  end

  def test_every_finding_is_attributed_to_exactly_one_surface
    attributed = LINT::SURFACES.sum { |surface| LINT.findings_for(surface).size }

    assert_equal LINT.findings.size, attributed,
                 "a finding belongs to no surface or to both, so a baseline cannot bound it"
  end

  # The gap this is here to close, stated as a number so closing it is visible.
  def test_the_face_sits_off_the_grid_the_apps_are_on
    face = LINT.counts_for("face").fetch("off_scale_space", 0)

    assert_operator face, :>=, 0
    assert_equal LINT.baselines_for("face").fetch("off_scale_space"), face,
                 "the face's spacing drift moved; the baseline is the record of it"
  end

  # --- the scale itself ---------------------------------------------------

  def test_the_declared_scale_is_a_scale
    assert_equal LINT.space_px.sort, LINT.space_px, "the space scale is not in order"
    assert_equal LINT.space_px.uniq, LINT.space_px, "a step is declared twice"
    assert_includes LINT.space_px, 0.0
    refute_empty LINT.radius_px
    refute_empty LINT.line_heights
  end

  # Above the hairlines, every step is on the 4px grid. That is the property
  # that makes two unrelated components line up without anyone coordinating.
  def test_the_space_scale_is_a_four_pixel_grid_above_the_hairlines
    off_grid = LINT.space_px.reject { |px| px <= 3 || (px % 4).zero? }
    assert_empty off_grid, "these steps put an edge on a fractional device pixel: #{off_grid.inspect}"
  end

  def test_the_radius_scale_is_a_subset_of_the_space_grid
    stray = LINT.radius_px - LINT.space_px
    assert_empty stray, "a corner radius off the space grid: #{stray.inspect}"
  end

  # Unitless only. An absolute line-height does not inherit, and brgen's 18px
  # root makes the mismatch larger here than in a default-root tree.
  def test_the_line_height_scale_is_unitless_and_bounded
    LINT.line_heights.each do |value|
      assert_kind_of Float, value
      assert_operator value, :>=, 1.0, "a line-height under 1 overlaps its own ascenders"
      assert_operator value, :<=, 2.0
    end
    assert_includes LINT.line_heights, 1.5, "1.5 carries 44 of the 83 declarations; it is the body rhythm"
  end

  def test_the_weight_scale_is_the_faces_that_are_loaded
    LINT.font_weights.each do |weight|
      assert_includes 100..900, weight
      assert_equal 0, weight % 100, "a weight off the 100 grid is synthesised"
    end
  end

  # --- the instrument -----------------------------------------------------
  #
  # Verify the instrument before the finding: every wrong number this lint has
  # produced so far came from the tokeniser, not from the tree.

  def test_it_is_reading_the_family_stylesheets
    sheets = LINT.stylesheets

    assert_operator sheets.size, :>, 50, "the sheet glob has stopped matching"
    %w[brgen amber bsdports shared].each do |app|
      assert sheets.any? { |p| p.include?("/#{app}/") }, "#{app}'s stylesheets are not being read"
    end
    assert_empty sheets.select { |p| p.match?(LINT::SKIP) }
  end

  def test_generated_and_vendored_output_is_not_source
    %w[
      /RAILS/brgen/app/assets/builds/application.css
      /RAILS/shared/node_modules/x/y.css
      /RAILS/brgen/public/assets/application-abc123.css
      /RAILS/amber/vendor/z.scss
    ].each { |path| assert_match LINT::SKIP, path }
  end

  def test_a_computed_value_is_not_a_step_someone_chose
    %w[
      calc(var(--space-sm)\ +\ 3px)
      clamp(16px,\ 5vw,\ 48px)
      var(--chrome-inset)
      env(safe-area-inset-bottom)
      min(100%,\ 37px)
    ].each do |value|
      assert_empty LINT.off_scale_lengths(value.tr("\\", " "), LINT.space_px),
                   "#{value} is computed; its innards are not author-chosen steps"
    end
  end

  def test_nested_computed_values_are_stripped_all_the_way_down
    assert_empty LINT.off_scale_lengths("calc(clamp(3px, 5vw, 7px) + max(1px, 9px))", LINT.space_px)
  end

  def test_a_real_off_scale_value_is_still_caught_beside_a_computed_one
    found = LINT.off_scale_lengths("calc(var(--x) + 4px) 0.35rem", LINT.space_px)
    assert_equal ["0.35rem"], found
  end

  def test_multi_value_shorthand_is_checked_per_step
    assert_empty LINT.off_scale_lengths("8px 12px 16px 4px", LINT.space_px)
    assert_equal ["0.65rem"], LINT.off_scale_lengths("8px 0.65rem", LINT.space_px)
  end

  def test_a_negative_pull_is_measured_by_magnitude
    assert_empty LINT.off_scale_lengths("-1px", LINT.space_px), "a hairline pull is on the scale"
    assert_equal ["-0.35rem"], LINT.off_scale_lengths("-0.35rem", LINT.space_px)
  end

  def test_zero_and_keywords_are_not_measured
    ["0", "auto", "inherit", "0 auto", "normal"].each do |value|
      assert_empty LINT.off_scale_lengths(value, LINT.space_px), "#{value} is not a step"
    end
  end

  def test_rem_and_px_spellings_of_one_step_agree
    assert_empty LINT.off_scale_lengths("0.75rem", LINT.space_px)
    assert_empty LINT.off_scale_lengths("12px", LINT.space_px)
  end

  # Same trap breakpoint_lint walked into: a paragraph explaining why a value
  # changed contains the value, and a lint that reports its own documentation
  # gets the documentation deleted.
  def test_comments_are_not_declarations
    Dir.mktmpdir do |dir|
      path = File.join(dir, "a.scss")
      File.write(path, "/* padding: 0.35rem was wrong */\n// gap: 0.65rem too\n.x { gap: 8px; }\n")
      lines = LINT.source_lines(path)

      assert_equal 3, lines.size, "line numbering did not survive comment blanking"
      assert_empty lines.first.strip
      assert_includes lines[2], "gap: 8px"
    end
  end

  def test_an_opt_out_silences_its_own_line_and_the_one_below
    lines = ["  gap: 0.35rem; // scale: ok\n", "  // scale: ok\n", "  gap: 0.65rem;\n", "  gap: 0.4rem;\n"]

    assert LINT.opted_out?(lines, 0)
    assert LINT.opted_out?(lines, 2), "the comment above a line opts that line out"
    refute LINT.opted_out?(lines, 3)
  end

  # The test above proves the helper and nothing else, which is how every opt-out
  # in the tree stayed inert: findings read the copy source_lines had blanked, so
  # `// scale: ok` was spaces by the time opted_out? looked for it. This one
  # crosses the real path.
  def test_an_opt_out_written_in_a_real_stylesheet_silences_that_line
    marked = LINT.stylesheets.flat_map do |path|
      File.readlines(path, encoding: "UTF-8").each_with_index.filter_map do |line, index|
        [ LINT.rel(path), index + 1 ] if line.include?(LINT::OPT_OUT)
      end
    end
    refute_empty marked, "no opt-out left in the tree; this test would prove nothing"

    silenced = marked.flat_map { |file, line| [ [ file, line ], [ file, line + 1 ] ] }
    loud = LINT.findings.select { |finding| silenced.include?([ finding.file, finding.line ]) }

    assert_empty loud.map { |f| "#{f.file}:#{f.line} #{f.property}: #{f.value}" },
                 "an opted-out line still reported"
  end

  # --- line-height --------------------------------------------------------

  def test_an_absolute_line_height_is_reported_as_its_own_kind
    found = LINT.check_line_height("a.scss", 1, "line-height", "28px")

    assert_equal 1, found.size
    assert_equal "absolute_line_height", found.first.kind
  end

  def test_a_unitless_line_height_on_the_scale_is_silent
    assert_empty LINT.check_line_height("a.scss", 1, "line-height", "1.5")
  end

  def test_a_unitless_line_height_off_the_scale_is_reported
    assert_equal "off_scale_line_height",
                 LINT.check_line_height("a.scss", 1, "line-height", "1.55").first.kind
  end

  def test_a_tokenised_line_height_is_the_tokens_problem_not_this_lint_s
    assert_empty LINT.check_line_height("a.scss", 1, "line-height", "var(--line-relaxed)")
  end

  # --- radius -------------------------------------------------------------

  def test_a_percentage_radius_is_a_shape_not_a_step
    ["50%", "100%", "50% 50%"].each do |value|
      assert_empty LINT.check_radius("a.scss", 1, "border-radius", value)
    end
  end

  def test_a_flat_corner_is_a_decision_the_scale_carries
    assert_empty LINT.check_radius("a.scss", 1, "border-radius", "0")
    assert_empty LINT.check_radius("a.scss", 1, "border-radius", "0 !important")
  end

  # --- reporting ----------------------------------------------------------

  # A finding that says only "wrong" costs the reader the arithmetic. The whole
  # value of a scale lint is that the right answer is computable.
  def test_a_finding_names_the_step_it_should_have_been
    finding = Pub4::ScaleLint::Finding.new("a.scss", 1, "off_scale_space", "0.35rem", "gap")
    assert_equal "4px", LINT.nearest(finding), "0.35rem is 5.6px, which is nearer 4 than 8"
  end

  # 3px sits exactly between the 2 and 4 of the radius scale. min_by keeps the
  # first minimum, so a tie resolves downward -- stated here because a suggestion
  # that flips between two answers on a scale reorder is worse than either.
  def test_a_tie_resolves_to_the_smaller_step
    radius = Pub4::ScaleLint::Finding.new("a.scss", 1, "off_scale_radius", "3px", "border-radius")
    assert_equal "2px", LINT.nearest(radius)
  end

  def test_a_kind_with_no_nearest_step_says_so_rather_than_guessing
    finding = Pub4::ScaleLint::Finding.new("a.scss", 1, "off_scale_line_height", "1.55", "line-height")
    assert_nil LINT.nearest(finding)
  end

  def test_every_finding_points_at_a_file_that_exists_and_a_real_line
    LINT.findings.first(40).each do |finding|
      # Repo-relative since the corpus spans MASTER/web as well as RAILS.
      path = File.join(Pub4::ScaleLint::REPO_ROOT, finding.file)
      assert File.file?(path), "#{finding.file} is not on disk"
      assert_operator finding.line, :>, 0
      assert_operator finding.line, :<=, File.readlines(path).size, "#{finding.file}:#{finding.line} is past EOF"
    end
  end

  # The ladder lived under `system:` with no reader, hand-copied into
  # _tokens.scss, and the copies drifted: the stylesheet carried a ninth step,
  # whisper, that the source of truth did not list. Two hand-maintained copies of
  # one scale is the defect this file exists to catch on every other axis.
  def test_the_stylesheet_declares_exactly_the_opacity_ladder
    declared = File.readlines(TOKENS_SCSS, encoding: "UTF-8")
                   .filter_map { |line| Float(Regexp.last_match(1)) if line =~ /--opacity-[\w-]+:\s*([\d.]+);/ }

    refute_empty declared, "no --opacity-* declarations found; this test would prove nothing"
    assert_equal LINT.scale.fetch("opacity").map { |v| Float(v) }.sort, declared.sort,
                 "_tokens.scss and design_tokens.yml scale.opacity disagree"
  end
end
