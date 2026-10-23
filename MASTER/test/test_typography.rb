# frozen_string_literal: true

require_relative "test_helper"
require "open3"
require_relative "../lib/design/typography"

class TypographyTest < Minitest::Test
  # The rendered geometry check loads this file in a bare process. Through for_surface every
  # micro-typography measurement raised NameError on Master::ROOT, 187 of them in one /fix RAILS run.
  def test_a_surfaces_context_reads_without_booting_master
    file = File.expand_path("../lib/design/typography.rb", __dir__)
    script = "require #{file.inspect}; print Master::Design::Typography.context_for(path: '/feed')[:text_wrap]"

    out, status = Open3.capture2e(RbConfig.ruby, "-e", script)

    assert status.success?, out
    assert_equal "pretty", out
  end

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
