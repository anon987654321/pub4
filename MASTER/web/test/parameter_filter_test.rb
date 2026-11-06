# frozen_string_literal: true

require "test_helper"

# The operator token and a pair code travel as the argument of a slash command,
# so the key-based filter never saw them and the production log held the token.
class ParameterFilterTest < ActiveSupport::TestCase
  def filtered(params)
    ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters).filter(params)
  end

  test "an unlock or pair argument is dropped and the verb kept" do
    assert_equal "/unlock [FILTERED]", filtered("command" => +"/unlock s3cret-token")["command"]
    assert_equal "/pair [FILTERED]", filtered("message" => +"/pair 4417")["message"]
  end

  test "ordinary chat is logged as written" do
    assert_equal "how do I /unlock a door?", filtered("message" => +"how do I /unlock a door?")["message"]
  end
end
