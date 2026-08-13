# frozen_string_literal: true

class Vote < ApplicationRecord
  tracks_activity created: "VoteCreated", source_vertical: "social", visibility: "private", actor: :user

  belongs_to :user
  belongs_to :votable, polymorphic: true, touch: true

  validates :value, inclusion: { in: [ -1, 1 ] }
  validates :user_id, uniqueness: { scope: [ :votable_type, :votable_id ] }

  after_save    :update_author_karma
  after_destroy :update_author_karma

  private

  # `votable.user` was a lazy belongs_to read on a votable the controller loaded
  # by id, and ApplicationRecord is strict_loading by default — so this raised
  # after the vote had already been written. It was invisible for as long as
  # VotesController#find_votable 404'd before ever reaching a save (post_vote_path
  # carries a slug, and find_votable called find). Fixing the 404 exposed it.
  #
  # votable is polymorphic, so Shared::StrictSafeAssociations#strict_safe does
  # not apply — it needs reflection.klass, which a polymorphic belongs_to has no
  # single answer for. Reading the author id off the table avoids instantiating
  # either record.
  def update_author_karma
    klass = votable_type.to_s.safe_constantize
    return unless klass.respond_to?(:column_names) && klass.column_names.include?("user_id")

    author_id = klass.where(id: votable_id).pick(:user_id)
    User.find_by(id: author_id)&.update_karma!
  end
end
