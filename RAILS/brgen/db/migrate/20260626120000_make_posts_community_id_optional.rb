# frozen_string_literal: true

class MakePostsCommunityIdOptional < ActiveRecord::Migration[8.0]
  def change
    change_column_null :posts, :community_id, true
  end
end