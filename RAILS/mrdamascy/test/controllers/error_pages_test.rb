# frozen_string_literal: true

require "test_helper"

# The static 404 and 500 pages cannot load the stylesheet, so they carry
# copies of the tokens they use; those copies must match _tokens.scss.
class ErrorPagesTest < ActiveSupport::TestCase
  test "the error pages use the app's tokens, flat" do
    %w[404 500].each do |code|
      page = Rails.public_path.join("#{code}.html").read
      root = page[/:root \{(.*?)\}/m, 1]
      assert root, "#{code}.html declares no tokens"

      root.scan(/(--[\w-]+): ([^;]+);/).each do |name, value|
        assert_equal ApplicationHelper::DESIGN_TOKENS.fetch(name), value, "#{code}.html #{name}"
      end
      rules = page.sub(root, "")
      assert_no_match(/#\h{3,6}\b|box-shadow|border-radius: \d/, rules, "#{code}.html: raw colour, shadow or radius")
      assert_includes rules, "font-family: var(--font)"
    end
  end
end
