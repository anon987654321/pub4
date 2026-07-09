# frozen_string_literal: true

class AddCityTenantColumns < ActiveRecord::Migration[8.1]
  TABLES = %i[posts users].freeze

  def up
    TABLES.each do |table|
      next if column_exists?(table, :city_id)

      add_reference table, :city, foreign_key: true, null: true
    end
  end

  def down
    TABLES.each do |table|
      remove_reference table, :city, foreign_key: true if column_exists?(table, :city_id)
    end
  end
end
