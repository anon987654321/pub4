# frozen_string_literal: true

require "test_helper"

# application.scss carried rules for markup no view renders (.jox-logo, the
# header .tabs strip), two .dep-graph blocks and two primary-nav aria-current
# rules that disagreed (the later one won), and blocks that said border: 0
# twice in a row.
class StylesheetTidyTest < ActiveSupport::TestCase
  SOURCE = Rails.root.join("app/assets/stylesheets/application.scss").read

  test "no rules for markup that is never rendered" do
    assert_no_match(/\.jox-logo/, SOURCE)
    assert_no_match(/^\s*\.tabs \{/, SOURCE)
  end

  test "the graph and the current nav link each have one definition" do
    assert_equal 1, SOURCE.scan(/^\.dep-graph \{/).size
    assert_equal 1, SOURCE.scan(/^nav\[data-pwa-primary-nav\] a\[aria-current\] \{/).size
  end

  test "no block repeats a declaration on consecutive lines" do
    lines = SOURCE.lines.map(&:strip)
    repeats = lines.each_cons(2).select { |a, b| a == b && a.match?(/\A[a-z-]+:.*;\z/) }
    assert_empty repeats
  end
end
