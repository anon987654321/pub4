# frozen_string_literal: true

require_relative "test_helper"
require File.expand_path("../tools/stale_exemptions", __dir__)

# EXEMPTIONS_EXPIRE was conduct with no detector, and the detector is mostly its
# reading of what counts as a marker. Every case here is one the first run got
# wrong and a person read by hand.
class TestStaleExemptions < Minitest::Test
  Census = Operator::StaleExemptions

  RUBY = ["#"].freeze
  SCSS = ["//", "/*"].freeze
  HTML = ["<%#", "<!--"].freeze

  # The census is of exemptions, and this repo writes about its own marker more
  # than most repos write about anything.
  def test_a_marker_named_in_prose_is_not_an_exemption
    assert Census.quoted?("# A line carrying `scan: intentional` opts that line out\n", RUBY)
    assert Census.quoted?(%(  assert_empty findings(:X, "v = 1 # scan: intentional — ok\\n")\n), RUBY)
  end

  # The bug that cost thirty live markers: `#` opens a comment in Ruby and is a
  # hex colour in SCSS, so one flat opener list read every coloured line as a
  # marker nested inside a `#` comment.
  def test_a_hex_colour_is_not_a_comment_opener
    refute Census.quoted?("  background: #131921; // scan: intentional — brand hex\n", SCSS)
    refute Census.quoted?(%(  Dir.glob("\#{LOG}.*").each { |f| File.delete(f) } # scan: intentional — rotation\n), RUBY)
  end

  # And the one that cost every ERB marker: the `#` in `<%#` is that opener, not
  # a second one inside it.
  def test_an_erb_comment_is_one_opener_not_two
    refute Census.quoted?("  <%# scan: intentional — generated markup %>\n", HTML)
  end

  # A marker on a line that is comment all the way through cannot work at all.
  # Rule#scan_lines skips the line the marker sits on, and the line it was
  # written about is the next one.
  def test_a_marker_with_no_code_beside_it_is_misplaced
    assert_empty Census.code_in("     height rather than snapping. scan: intentional */\n", SCSS)
    assert_empty Census.code_in("  <%# scan: intentional — @qr is generated SVG\n", HTML)
  end

  # The tail half: amber's logo closes its ERB comment and carries markup after
  # it on the same line, so that marker does sit beside code.
  def test_code_after_a_closed_comment_still_counts
    line = %(    <%# scan: intentional — the wordmark %><textPath href="#p">amber</textPath>\n)

    assert_includes Census.code_in(line, HTML), "<textPath"
  end

  def test_a_trailing_marker_reports_the_code_it_sits_beside
    assert_equal "body = read_utf8(path)",
                 Census.code_in("        body = read_utf8(path) # scan: intentional — two plain lines\n", RUBY)
  end

  # Stripping keeps the line so every line number still points where it did — a
  # census that shifted them would report findings against the wrong markers.
  def test_stripping_a_marker_keeps_the_line_count
    text = "a = 1\nb = 2 # scan: intentional — deliberate\nc = 3\n"
    stripped = Census.unmarked(text)

    assert_equal text.lines.size, stripped.lines.size
    assert_equal "b = 2", stripped.lines[1].chomp
  end

  def test_the_suffixed_directives_are_a_different_instruction
    refute_match Census::MARKER, "/* scan: intentional-colors */"
    refute_match Census::MARKER, "// scan: intentional-important"
    assert_match Census::MARKER, "value = 1 # scan: intentional — deliberate"
  end

  # The strip cut `  <%# scan: … ` at the `#` inside `<%#` and left a bare `<%`,
  # which opened an ERB tag over the rest of a multi-line comment. ERB_HTML_SAFE
  # looks for a sanitizing call inside a tag, so it then matched the word
  # "sanitize" in that comment's second line and stayed silent — the 2FA
  # exemption read as stale because the strip built the thing that silenced it.
  def test_stripping_an_erb_marker_does_not_leave_an_open_tag
    stripped = Census.unmarked("  <%# scan: intentional — why\n      because sanitize strips svg %>\n", HTML)

    refute_includes stripped.lines.first, "<%"
    assert_equal 2, stripped.lines.size
  end

  def test_the_reason_is_read_out_of_the_marker
    assert_equal "log rotation", Census.reason_in("x # scan: intentional — log rotation\n")
    assert_equal "brand hex", Census.reason_in("  color: #fff; /* scan: intentional — brand hex */\n")
  end
end
