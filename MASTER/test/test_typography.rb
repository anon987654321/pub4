# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/design/typography"

class TypographyTest < Minitest::Test
  def test_profiles_are_contextual
    editorial = Master::Design::Typography.profile(:editorial)
    social = Master::Design::Typography.profile(:social)

    assert_equal 66, editorial[:measure]
    assert_equal 55, social[:measure]
    assert_equal "hanging", editorial[:punctuation]
  end

  def test_route_profile_does_not_turn_chrome_into_prose
    legal = Master::Design::Typography.for_surface(path: "/privacy")
    market = Master::Design::Typography.for_surface(path: "/items/new")

    assert_equal "oldstyle-nums", legal[:numerals]
    assert_equal 50, market[:measure]
  end

  def test_brief_is_machine_readable_and_human_readable
    brief = Master::Design::Typography.brief(path: "/feed")

    assert_includes brief, "measure=55ch"
    assert_includes brief, "wrap=pretty"
    assert_includes brief, "justification=never"
  end
end
