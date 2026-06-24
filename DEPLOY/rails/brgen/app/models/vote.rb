# frozen_string_literal: true

class Vote < ApplicationRecord
  include Shared::ActivityTrackable
  tracks_activity created: "VoteCreated", source_vertical: "social", visibility: "private", actor: :user

  belongs_to :user
  belongs_to :votable, polymorphic: true, touch: true

  validates :value, inclusion: { in: [ -1, 1 ] }
  validates :user_id, uniqueness: { scope: [ :votable_type, :votable_id ] }

  after_save    :update_author_karma
  after_destroy :update_author_karma

  private

  def update_author_karma
    votable.user.update_karma! if votable.respond_to?(:user)
  end
end
