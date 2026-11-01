# frozen_string_literal: true

require "test_helper"
require "stringio"

class EmptyStateDeprecationTest < ActiveSupport::TestCase
  test "legacy actions local logs a deprecation" do
    original_logger = Rails.logger
    output = StringIO.new
    Rails.logger = ActiveSupport::Logger.new(output)

    ApplicationController.render(
      partial: "shared/empty_state",
      locals: { title: "No items", actions: "Browse items" }
    )

    assert_includes output.string,
                    "[DEPRECATION] shared/empty_state actions: use action: { label:, path: }"
  ensure
    Rails.logger = original_logger if original_logger
  end
end
