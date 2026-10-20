# frozen_string_literal: true

class Vote < ApplicationRecord
  belongs_to :user
  belongs_to :votable, polymorphic: true, touch: true

  validates :value, inclusion: { in: [ -1, 1 ] }
  validates :user_id, uniqueness: { scope: [ :votable_type, :votable_id ] }

  after_save :apply_score_delta
  after_destroy :apply_score_delta

  private

  def apply_score_delta
    klass = votable_type.to_s.safe_constantize
    return unless klass.respond_to?(:column_names) && klass.column_names.include?("score")

    delta =
      if destroyed?
        -value.to_i
      else
        before, after = saved_change_to_value
        after.to_i - before.to_i
      end
    return if delta.zero?

    klass.where(id: votable_id).update_all([ "score = COALESCE(score, 0) + ?", delta ])
  end
end
