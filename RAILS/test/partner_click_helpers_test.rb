# frozen_string_literal: true

require "minitest/autorun"

# :marketplace.listing_path is Symbol#listing_path, which does not exist.
# The show action rescued that and always fell through to /listings/:id.
class PartnerClickHelpersTest < Minitest::Test
  SOURCE = File.expand_path("../brgen/app/controllers/partner/clicks_controller.rb", __dir__)

  def test_does_not_call_listing_path_on_a_symbol
    src = File.read(SOURCE)
    refute_match(/respond_to\?\(:marketplace\./, src)
    assert_includes src, "respond_to?(:marketplace)"
  end
end
