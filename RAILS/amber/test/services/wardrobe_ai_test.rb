# frozen_string_literal: true

require "test_helper"

class WardrobeAiTest < ActiveSupport::TestCase
  class FakeClient
    def initialize(content: nil, error: nil)
      @content = content
      @error = error
    end

    def chat(parameters:)
      raise @error if @error

      {
        "choices" => [
          { "message" => { "content" => @content } }
        ]
      }
    end
  end

  test "analyze_joy uses local heuristic when no API key is configured" do
    item = Item.new(title: "Blue jacket", category: "Outerwear", times_worn: 0)
    service = WardrobeAi.new(User.new, client: nil)

    result = service.analyze_joy(item)

    assert_equal false, result["sparks_joy"]
    assert_equal "heuristic", result["source"]
    assert result["reason"].present?
    assert result["suggestion"].present?
  end

  test "analyze_joy heuristic keeps high-wear items as joy" do
    item = Item.new(title: "Jeans", category: "Bottoms", times_worn: 12)
    result = WardrobeAi.new(User.new, client: nil).analyze_joy(item)

    assert_equal true, result["sparks_joy"]
    assert_equal "heuristic", result["source"]
  end

  test "chat-backed methods tolerate invalid JSON" do
    item = Item.new(title: "Blue jacket", category: "Outerwear")
    client = FakeClient.new(content: "not json")
    service = WardrobeAi.new(User.new, client: client)

    result = service.analyze_joy(item)

    assert_nil result["sparks_joy"]
    assert_equal "Analysis unavailable", result["reason"]
    assert_equal "Trust your instincts", result["suggestion"]
  end

  test "suggest_outfits returns an empty array when wardrobe empty and provider fails" do
    user = User.new
    def user.items = Item.none

    service = WardrobeAi.new(user, client: FakeClient.new(error: StandardError.new("boom")))

    assert_equal [], service.suggest_outfits
  end

  test "fingerprint_for is deterministic and not claimed as embedding provider" do
    item = Item.new(title: "Coat", category: "Outerwear", color: "navy")
    a = WardrobeAi.new(User.new).fingerprint_for(item)
    b = WardrobeAi.new(User.new).fingerprint_for(item)

    assert_equal 64, a.length
    assert_equal a, b
  end

  test "configured? reflects OPENROUTER_API_KEY" do
    old = ENV["OPENROUTER_API_KEY"]
    ENV["OPENROUTER_API_KEY"] = ""
    refute WardrobeAi.configured?
    ENV["OPENROUTER_API_KEY"] = "sk-test"
    assert WardrobeAi.configured?
  ensure
    ENV["OPENROUTER_API_KEY"] = old
  end
end
