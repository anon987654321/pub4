# frozen_string_literal: true

class AddMaintainerToPorts < ActiveRecord::Migration[8.1]
  def change
    add_reference :ports, :maintainer, foreign_key: true, null: true
  end
end
