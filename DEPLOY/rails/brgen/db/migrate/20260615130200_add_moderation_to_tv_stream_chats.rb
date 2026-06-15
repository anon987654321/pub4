# frozen_string_literal: true

class AddModerationToTvStreamChats < ActiveRecord::Migration[8.1]
  def change
    add_column :tv_stream_chats, :moderation_status, :string, null: false, default: "visible"
    add_column :tv_stream_chats, :moderated_at, :datetime
    add_column :tv_stream_chats, :moderated_by_id, :integer
    add_index :tv_stream_chats, :moderation_status
  end
end