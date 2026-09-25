# frozen_string_literal: true

class AddDinteroSplitJson < ActiveRecord::Migration[8.1]
  def change
    add_column :marketplace_orders, :dintero_split_json, :text
  end
end
