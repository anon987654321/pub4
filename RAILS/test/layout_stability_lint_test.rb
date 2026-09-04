# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../shared/lib/pub4/layout_stability_lint"

# Whether the layout holds still, asserted from source.
#
# The tree has visual gates already, and every one of them measures a finished
# frame: design_contract reads the compiled CSS, visual_contract_gate reads a
# rendered screenshot. A finished frame cannot show a shift, because by the time
# it is finished the shift has happened and the reader has already lost their
# place. This asks the question the frame cannot answer -- is there anything on
# this page whose size is unknown until the network answers.
class LayoutStabilityLintTest < Minitest::Test
  LINT = Pub4::LayoutStabilityLint

  def counts = @counts ||= LINT.counts

  def test_no_kind_exceeds_its_baseline
    regressions = LINT::BASELINES.filter_map do |kind, baseline|
      count = counts.fetch(kind, 0)
      next if count <= baseline

      examples = LINT.findings.select { |f| f.kind == kind }.first(6)
                     .map { |f| "#{f.file}:#{f.line} #{f.detail}" }
      "#{kind}: #{count}, baseline #{baseline}\n    #{examples.join("\n    ")}"
    end

    assert_empty regressions, "something new can move after paint:\n  #{regressions.join("\n  ")}"
  end

  def test_baselines_are_not_stale
    stale = LINT::BASELINES.filter_map do |kind, baseline|
      count = counts.fetch(kind, 0)
      "#{kind}: #{count} found, baseline still #{baseline}" if count < baseline
    end

    assert_empty stale, "lower these in layout_stability_lint.rb:\n  #{stale.join("\n  ")}"
  end

  def test_every_kind_is_bounded
    assert_empty counts.keys - LINT::BASELINES.keys
  end

  # The one that is already closed. Ten @font-face blocks, all with a display
  # strategy -- this asserts it stays that way rather than congratulating it.
  def test_no_web_font_blocks_its_own_text
    assert_equal 0, counts.fetch("font_without_display", 0),
                 "font-display defaults to auto, which most browsers render as block: " \
                 "invisible text for up to three seconds, then a reflow"
  end

  # --- the instrument -----------------------------------------------------

  def test_it_is_reading_both_corpora
    assert_operator LINT.views.size, :>, 300, "the view glob has stopped matching"
    assert_operator LINT.stylesheets.size, :>, 50, "the stylesheet glob has stopped matching"
    %w[brgen amber bsdports shared].each do |app|
      assert LINT.views.any? { |p| p.include?("/#{app}/") }, "#{app}'s views are not being read"
    end
  end

  def test_the_reservation_index_is_populated
    reserved = LINT.reserved_classes

    assert_operator reserved.size, :>, 50,
                    "no class reserves a box, which means the SCSS parse is returning nothing"
    assert_kind_of Set, reserved
  end

  def test_a_class_with_an_aspect_ratio_counts_as_reserved
    Dir.mktmpdir do |dir|
      path = File.join(dir, "a.scss")
      File.write(path, ".hero-img { aspect-ratio: 16 / 9; }\n.plain { color: red; }\n")
      body = LINT.strip_comments(File.read(path))
      reserved = Set.new
      body.scan(/([^{}]+)\{([^{}]*)\}/m) do |sel, block|
        sel.scan(/\.([a-zA-Z][\w-]*)/) { |n| reserved << n.first } if block.match?(LINT::RESERVING)
      end

      assert_includes reserved, "hero-img"
      refute_includes reserved, "plain", "a colour is not a reservation"
    end
  end

  # `line-height` and `max-height` both contain "height"; only an actual height
  # reserves the box, and a lookbehind is the whole difference.
  def test_a_property_that_merely_contains_height_is_not_a_reservation
    refute_match LINT::RESERVING, "line-height: 1.5;"
    refute_match LINT::RESERVING, "border-block-end-width: 1px;"
    assert_match LINT::RESERVING, "height: 240px;"
    assert_match LINT::RESERVING, "aspect-ratio: 1;"
    assert_match LINT::RESERVING, "contain-intrinsic-size: 0 300px;"
  end

  # --- sizing recognition -------------------------------------------------

  def test_explicit_attributes_count_as_sized
    assert LINT.sized?('<img src="a.png" width="80" height="80">')
    assert LINT.sized?('image_tag "a.png", width: 80, height: 80')
    assert LINT.sized?('image_tag "a.png", size: "80x80"')
  end

  def test_a_width_without_a_height_does_not_reserve_a_box
    refute LINT.sized?('<img src="a.png" width="80">'),
           "a width alone leaves the height to the image, which is the shift"
  end

  def test_an_inline_aspect_ratio_counts
    assert LINT.sized?('<img src="a.png" style="aspect-ratio: 1 / 1">')
  end

  def test_a_reserved_class_counts
    reserved = LINT.reserved_classes.first
    skip "no reserved classes in this tree" unless reserved

    assert LINT.sized?(%(<img src="a.png" class="#{reserved}">))
  end

  def test_an_unknown_class_does_not
    refute LINT.sized?('<img src="a.png" class="class-that-does-not-exist-anywhere">')
  end

  # --- transitions --------------------------------------------------------

  def test_a_compositor_only_transition_is_silent
    Dir.mktmpdir do |dir|
      path = File.join(dir, "a.scss")
      File.write(path, ".x { transition: transform 200ms ease, opacity 200ms ease; }\n")
      value = File.read(path)[LINT::TRANSITION, 1]

      assert_empty LINT::LAYOUT_PROPS.select { |p| value.match?(/(?<![-\w])#{Regexp.escape(p)}(?![-\w])/) }
    end
  end

  def test_all_is_treated_as_a_layout_transition
    value = "all 160ms var(--ease-out)"
    assert_includes LINT::LAYOUT_PROPS.select { |p| value.match?(/(?<![-\w])#{Regexp.escape(p)}(?![-\w])/) }, "all"
  end

  # `max-width` contains `width`; both are layout properties so both are named,
  # but a transition on `transform` must not be read as one because the word
  # appears inside another token.
  def test_a_property_name_inside_another_token_is_not_a_match
    value = "grid-template-columns 200ms"
    named = LINT::LAYOUT_PROPS.select { |p| value.match?(/(?<![-\w])#{Regexp.escape(p)}(?![-\w])/) }

    assert_empty named, "matched a substring of a longer property name"
  end

  # --- shared conventions -------------------------------------------------

  def test_comments_are_not_source
    Dir.mktmpdir do |dir|
      path = File.join(dir, "a.scss")
      File.write(path, "/* transition: all 1s */\n// transition: width 1s\n.x { color: red; }\n")
      lines = LINT.source_lines(path)

      assert_equal 3, lines.size
      assert_empty lines[0].strip
      assert_empty lines[1].strip
    end
  end

  def test_an_opt_out_covers_its_line_and_the_one_below
    lines = ["<img src=a>  <%# layout: ok %>\n", "<%# layout: ok %>\n", "<img src=b>\n", "<img src=c>\n"]

    assert LINT.opted_out?(lines, 0)
    assert LINT.opted_out?(lines, 2)
    refute LINT.opted_out?(lines, 3)
  end

  def test_every_finding_points_at_a_real_line
    LINT.findings.first(40).each do |finding|
      path = File.join(Pub4::LayoutStabilityLint::RAILS_ROOT, finding.file)
      assert File.file?(path), "#{finding.file} is not on disk"
      assert_operator finding.line, :>, 0
      assert_operator finding.line, :<=, File.readlines(path).size
    end
  end

  def test_findings_carry_enough_to_act_on
    LINT.findings.each do |finding|
      refute_empty finding.detail.to_s.strip, "#{finding.file}:#{finding.line} says only that something is wrong"
      assert_includes LINT::BASELINES.keys, finding.kind
    end
  end

  # The opt-out was read from the comment-stripped copy, so a marker -- itself a
  # comment -- was blanked before anything looked for it. ScaleLint carried the
  # same bug and three real markers turned out to silence nothing. This asserts
  # through the tree rather than a fixture, because a fixture is what passed
  # last time.
  def test_a_reserved_marker_written_in_a_real_view_silences_that_tag
    marked = LINT.views.flat_map do |path|
      File.readlines(path, encoding: "UTF-8").each_with_index.filter_map do |line, index|
        [ LINT.rel(path), index + 2 ] if line.include?(LINT::RESERVED)
      end
    end
    refute_empty marked, "no reserved: marker left in the tree; this test would prove nothing"

    loud = LINT.findings.select { |finding| marked.include?([ finding.file, finding.line ]) }

    assert_empty loud.map { |finding| "#{finding.file}:#{finding.line} #{finding.detail}" },
                 "a tag marked reserved is still reported"
  end
end
