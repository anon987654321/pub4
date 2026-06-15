# frozen_string_literal: true

class AddOnboardingToUsers < ActiveRecord::Migration[8.1]
  def change
    change_table :users, bulk: true do |t|
      t.datetime :onboarding_completed_at
      t.string :onboarding_city_slug
      t.json :onboarding_interests, default: []
      t.json :onboarding_verticals, default: []
    end
  end
end