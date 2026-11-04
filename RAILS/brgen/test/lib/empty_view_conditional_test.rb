# frozen_string_literal: true

require "test_helper"

# A conditional with nothing inside renders nothing either way and only costs
# a reader the time to find that out. The legal footer ended with one, an
# email-subscriptions check with no body.
class EmptyViewConditionalTest < ActiveSupport::TestCase
  EMPTY = /<%-?\s*(?:if|unless)\b[^%]*%>\s*<%-?\s*end\s*-?%>/

  test "no shared or app view holds an empty if or unless block" do
    rails = Rails.root.join("..")
    views = Dir[rails.join("{__shared,brgen,amber,bsdports}/app/views/**/*.erb").to_s]
    empty = views.select { |path| File.read(path).match?(EMPTY) }

    refute_empty views
    assert_empty empty.map { |path| path.delete_prefix("#{rails.expand_path}/") }
  end
end
