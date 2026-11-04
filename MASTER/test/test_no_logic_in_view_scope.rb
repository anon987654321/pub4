# frozen_string_literal: true

require_relative "test_helper"
require "review/scan/law_tree"

# NO_LOGIC_IN_VIEW matched `<%[^=].*where`, so an ERB comment explaining where
# a partial renders, or page text after `%>`, read as a query in the view.
class TestNoLogicInViewScope < Minitest::Test
  PATH = "/repo/app/views/posts/index.html.erb"
  FIXTURES = File.join(__dir__, "fixtures", "no_logic_in_view")

  def lines_for(name)
    src = File.read(File.join(FIXTURES, name))
    ::Law.definitions.fetch(:NO_LOGIC_IN_VIEW).scan(src, file: PATH).map(&:line)
  end

  def test_comments_and_page_text_are_not_logic
    assert_empty lines_for("prose.html.erb")
  end

  def test_a_query_in_a_code_tag_is_still_found
    assert_equal [2], lines_for("query.html.erb")
  end
end
