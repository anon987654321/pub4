# frozen_string_literal: true

# IRC-style public channels ride on the existing group Conversation + Message
# stack. A channel is a group conversation with a stable `slug` and a `vertical`.
# Bot participants are Users flagged `bot` with a `persona` steering their voice.
class AddChannelsAndBots < ActiveRecord::Migration[8.1]
  def change
    add_column :conversations, :slug, :string
    add_column :conversations, :vertical, :string
    add_index :conversations, :slug, unique: true

    add_column :users, :bot, :boolean, default: false, null: false
    add_column :users, :persona, :text
  end
end
