# frozen_string_literal: true

require "test_helper"

# The brand mark's accessible name is the wordmark it shows (WCAG 2.5.3):
# an aria-label of "Home" or "Brgen hjem" replaced the visible word, so a
# speech-control user saying "brgen" found no link of that name.
class BrandMarkNameTest < ActionDispatch::IntegrationTest
  test "the brand mark is named by its visible wordmark" do
    %w[brgen.no lsangeles.com].each do |host|
      host! host
      get "/privacy"

      assert_response :success
      mark = css_select("a.brand-mark").first
      refute_nil mark, "#{host} renders the brand mark"
      assert_nil mark["aria-label"], "#{host}: an aria-label would replace the wordmark in the name"
      assert_equal host.split(".").first, mark.css(".brand-text").text.strip
    end
  end
end
