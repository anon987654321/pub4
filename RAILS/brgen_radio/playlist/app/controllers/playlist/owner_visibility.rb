# frozen_string_literal: true

# A set or playlist whose owner has deleted the account, or scheduled its
# deletion, is gone to strangers even though its own privacy says public.
module Playlist::OwnerVisibility
  private

  def owner_active?
    owner = (@set || @playlist)&.user
    owner.present? && owner.deleted_at.nil? && owner.deletion_scheduled_at.nil?
  end
end
