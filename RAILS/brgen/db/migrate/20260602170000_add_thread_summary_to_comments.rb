# frozen_string_literal: true

class AddThreadSummaryToComments < ActiveRecord::Migration[8.1]
  def change
    add_column :comments, :thread_summary, :text
    add_column :comments, :summary_updated_at, :datetime
  end
end
