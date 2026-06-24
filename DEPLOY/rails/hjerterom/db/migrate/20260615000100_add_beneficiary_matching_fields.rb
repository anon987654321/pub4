# frozen_string_literal: true

class AddBeneficiaryMatchingFields < ActiveRecord::Migration[8.0]
  def change
    add_column :beneficiaries, :dietary_restrictions, :text
    add_reference :food_items, :beneficiary, foreign_key: true
    add_column :food_items, :dietary_tags, :text
    add_column :food_items, :status, :string, null: false, default: "available"
  end
end
