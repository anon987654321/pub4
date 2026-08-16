# frozen_string_literal: true

require_relative "test_helper"

# NO_MULTIPLE_LANGUAGES matched every `<%`, so it reported 6,619 of the 14,552
# findings across RAILS and no Rails view could ever have cleared it. A gate
# whose zero is unreachable measures nothing. What it means to catch is a
# second language inside a file, which an inline <script> or <style> still is.
class NoMultipleLanguagesTest < Minitest::Test
  def rule
    @rule ||= Master::Review::Scan::InfraHelpers.build_scanner(root: Master::ROOT)
                                                .rules.find { |r| r.id.to_s == "NO_MULTIPLE_LANGUAGES" }
  end

  def findings(src, path) = Array(rule.check(src, path: path))

  def test_a_template_is_allowed_to_be_a_template
    assert_empty findings(%(<h1><%= t("title") %></h1>\n<p><%= @body %></p>\n), "app/views/x.html.erb")
  end

  def test_an_inline_script_in_a_template_is_still_a_second_language
    refute_empty findings(%(<script>alert(1)</script>\n), "app/views/x.html.erb")
  end

  def test_an_inline_style_in_a_template_is_still_a_second_language
    refute_empty findings(%(<style>.x { color: red }</style>\n), "app/views/x.html.erb")
  end

  def test_an_erb_tag_outside_a_template_is_still_mixed_medium
    refute_empty findings(%(template = "<%= x %>"\n), "lib/thing.rb")
  end
end
