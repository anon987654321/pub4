# frozen_string_literal: true

require "minitest/autorun"

# Write endpoints that had no rate limit at all (refinements brgen-065, 078, 086,
# 098, 130): dating likes and passes, verification requests, event RSVPs,
# remote fediverse follows and place check-ins. Each must declare a named
# rate_limit covering its action; RateLimitNamingTest keeps the names distinct.
class WriteEndpointRateLimitsTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  LIMITED = {
    "brgen_dating/app/controllers/dating/likes_controller.rb" => :create,
    "brgen_dating/app/controllers/dating/dislikes_controller.rb" => :create,
    "brgen_dating/app/controllers/dating/verifications_controller.rb" => :create,
    "brgen/app/controllers/event_rsvps_controller.rb" => :create,
    "brgen/app/controllers/fediverse/follows_controller.rb" => :create,
    "brgen_maps/app/controllers/maps/places_controller.rb" => :check_in,
  }.freeze

  def test_each_write_endpoint_declares_a_named_rate_limit_for_its_action
    LIMITED.each do |path, action|
      source = File.read(File.join(ROOT, path))
      declaration = source[/^\s*rate_limit\b[^\n]*\bonly: :#{action}\b[^\n]*/]
      assert declaration, "#{path} has no rate_limit on :#{action}"
      assert_match(/name: "\w+"/, declaration, "#{path}'s rate_limit is unnamed")
    end
  end
end
