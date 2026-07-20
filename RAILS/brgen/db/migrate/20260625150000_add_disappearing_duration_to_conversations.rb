# frozen_string_literal: true

class AddDisappearingDurationToConversations < ActiveRecord::Migration[8.1]
  def change
    return if column_exists?(:conversations, :disappearing_duration)

    add_column :conversations, :disappearing_duration, :integer
  end
end
