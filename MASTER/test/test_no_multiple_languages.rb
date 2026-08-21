# frozen_string_literal: true

require_relative "test_helper"

# NO_MULTIPLE_LANGUAGES matched every `<%`, so it reported 6,619 of the 14,552
# findings across RAILS and no Rails view could ever have cleared it. A gate
# whose zero is unreachable measures nothing.
#
# Since the 2026-08-21 twin retirement the duty is split where the law files
# say it is: NO_MULTIPLE_LANGUAGES (law/css.rb) reads code files for a second
# grammar — an ERB tag or an opening heredoc that smuggles SQL — and never
# reads templates at all, because a template is two languages by definition.
# The inline <script>/<style> case in a template is NO_INLINE_SCRIPT_BLOCK
# (law/html.rb), whose detector can be honest about what it wants.
class NoMultipleLanguagesTest < Minitest::Test
  def test_a_template_is_allowed_to_be_a_template
    src = %(<h1><%= t("title") %></h1>\n<p><%= @body %></p>\n)
    assert_empty law_findings("NO_MULTIPLE_LANGUAGES", src, path: "app/views/x.html.erb")
    assert_empty law_findings("NO_INLINE_SCRIPT_BLOCK", src, path: "app/views/x.html.erb")
  end

  def test_an_inline_script_in_a_template_is_still_a_second_language
    refute_empty law_findings("NO_INLINE_SCRIPT_BLOCK", %(<script>alert(1)</script>\n), path: "app/views/x.html.erb")
  end

  def test_an_inline_style_in_a_template_is_still_a_second_language
    refute_empty law_findings("NO_INLINE_SCRIPT_BLOCK", %(<style>.x { color: red }</style>\n), path: "app/views/x.html.erb")
  end

  def test_an_erb_tag_outside_a_template_is_still_mixed_medium
    refute_empty law_findings("NO_MULTIPLE_LANGUAGES", %(template = "<%= x %>"\n), path: "lib/thing.rb")
  end

  def test_an_opening_sql_heredoc_is_a_second_grammar
    refute_empty law_findings("NO_MULTIPLE_LANGUAGES", %(rows = db.execute(<<~SQL)\n), path: "lib/thing.rb")
  end

  def test_a_heredoc_closing_delimiter_is_not
    assert_empty law_findings("NO_MULTIPLE_LANGUAGES", %(  SQL\n), path: "lib/thing.rb")
  end
end
