# frozen_string_literal: true

require "test_helper"

class StyleEvolutionServiceTest < ActiveSupport::TestCase
  test "timeline groups items by life phase" do
    user = User.strict_loading(false).create!(email_address: "timeline@example.com", password: "password")
    user.items.destroy_all
    user.items.create!(title: "Blazer", category: "Outerwear", life_phase: "current")
    user.items.create!(title: "Vintage tee", category: "Tops", life_phase: "past-self")

    timeline = StyleEvolutionService.new(user).timeline

    current = timeline[:phases].find { |group| group[:phase] == "current" }
    past = timeline[:phases].find { |group| group[:phase] == "past-self" }

    assert_equal 1, current[:count]
    assert_equal 1, past[:count]
    assert_equal "Blazer", current[:items].first[:title]
  end
end