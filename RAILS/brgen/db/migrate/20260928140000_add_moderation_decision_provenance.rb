# frozen_string_literal: true

class AddModerationDecisionProvenance < ActiveRecord::Migration[8.1]
  def change
    add_column :moderation_reports, :decision_reason, :text
    add_column :moderation_reports, :decided_at, :datetime
  end
end
