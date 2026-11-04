# frozen_string_literal: true

require "test_helper"

# StyleEvolution#wear_timeline asked a wear log's outfit for #title, which
# Outfit does not have (it has a name), so the timeline page raised as soon
# as any wear was logged with an outfit.
class StyleEvolutionOutfitTest < ActiveSupport::TestCase
  test "a wear logged with an outfit names the outfit" do
    email = "se-#{SecureRandom.hex(4)}@example.test"
    user = User.strict_loading(false).create!(email_address: email, password: "password")
    shirt = user.items.create!(title: "Linskjorte", category: "Tops")
    outfit = Outfit.strict_loading(false).create!(user:, name: "Fredag")
    shirt.wear!(worn_on: Date.current, outfit:)

    events = StyleEvolution.new(user).timeline[:wear_events]
    assert_equal [ "Fredag" ], events.map { |event| event[:outfit_title] }
  end
end
