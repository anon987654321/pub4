# frozen_string_literal: true

# The messenger inbox. Last of the four feeds still on a pager, and the one that
# needed a partial extracted first — the rows were inline in conversations/index
# and the spine renders one partial per record.
#
# Scope copied from ConversationsController#index, INBOX_ORDER included: pins
# first, then newest message via a correlated subquery. Ordering in Ruby after
# the fact pins nothing on page two, because the page is chosen before the sort,
# and a reflex that ordered differently from the controller would append rows
# that do not follow from the ones above them.
class ConversationsInfiniteScrollReflex < Shared::InfiniteScrollReflex
  renders "conversations/conversation_row", as: :conversation

  private

  def scope
    Conversation.for_user(Current.user)
                .where(slug: nil)
                .includes(:participants, :messages)
                .order(Conversation::INBOX_ORDER)
  end

  # Both are per-page batch reads, for the reason the controller records: the
  # row used to ask each conversation for its own unread count, which is a
  # find_by plus a COUNT that `includes(:messages)` does not help with. One
  # grouped COUNT and one pluck for the whole appended page instead.
  def after_paginate
    @unread_counts = Conversation.unread_counts_for(Current.user)
    @pinned_ids = ConversationParticipant.pinned
                                         .where(user_id: Current.user.id,
                                                conversation_id: @records.map(&:id))
                                         .pluck(:conversation_id).to_set
  end

  def row_locals(conversation)
    {
      conversation: conversation,
      unread: @unread_counts.fetch(conversation.id, 0),
      pinned: @pinned_ids.include?(conversation.id),
    }
  end
end
