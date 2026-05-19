# frozen_string_literal: true

require "test_helper"

class WardrobeAiServiceTest < ActiveSupport::TestCase
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

  test "analyze_joy returns safe defaults when no API key is configured" do
    item = Item.new(title: "Blue jacket", category: "Outerwear")
    service = WardrobeAiService.new(User.new)

    result = service.analyze_joy(item)

    assert_nil result["sparks_joy"]
    assert_equal "Analysis unavailable", result["reason"]
    assert_equal "Trust your instincts", result["suggestion"]
  end

  test "chat-backed methods tolerate invalid JSON" do
    item = Item.new(title: "Blue jacket", category: "Outerwear")
    client = FakeClient.new(content: "not json")
    service = WardrobeAiService.new(User.new, client: client)

    result = service.analyze_joy(item)

    assert_nil result["sparks_joy"]
    assert_equal "Analysis unavailable", result["reason"]
    assert_equal "Trust your instincts", result["suggestion"]
  end

  test "suggest_outfits returns an empty array when provider fails" do
    user = User.new
    def user.items = Item.none

    service = WardrobeAiService.new(user, client: FakeClient.new(error: StandardError.new("boom")))

    assert_equal [], service.suggest_outfits
  end
end
