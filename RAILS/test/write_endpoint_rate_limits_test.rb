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
    "brgen/app/controllers/stories_controller.rb" => :create,
    "brgen/app/controllers/story_replies_controller.rb" => :create,
  }.freeze

  def test_each_write_endpoint_declares_a_named_rate_limit_for_its_action
    LIMITED.each do |path, action|
      source = File.read(File.join(ROOT, path))
      declaration = source[/^\s*rate_limit\b[^\n]*\bonly: :#{action}\b[^\n]*/]
      assert declaration, "#{path} has no rate_limit on :#{action}"
      assert_match(/name: "\w+"/, declaration, "#{path}'s rate_limit is unnamed")
    end  end

  # Comments carried one unnamed burst limit on :create and one unnamed limit on
  # :generate_summary, so both shared a counter for a signed-out commenter, and
  # there was no sustained limit as posts and messages have.
  def test_comments_carry_named_burst_and_sustained_limits
    source = File.read(File.join(ROOT, "brgen/app/controllers/comments_controller.rb"))
    declarations = source.scan(/^\s*rate_limit\b[^\n]*/)
    assert_equal 3, declarations.size
    declarations.each { assert_match(/name: "\w+"/, _1, "comments_controller has an unnamed rate_limit") }
    sustained = declarations.any? { _1.include?("within: 3.minutes, only: :create") }
    assert sustained, "comments#create has no sustained limit"
  end
end
