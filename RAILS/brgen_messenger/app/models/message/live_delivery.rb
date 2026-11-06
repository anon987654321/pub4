# frozen_string_literal: true

class Message
  # How a message reaches the people who are looking: appended to every open
  # log, replaced there on an edit or an unsend, and its thread's row redrawn in
  # each reader's inbox.
  module LiveDelivery
    extend ActiveSupport::Concern

    included do
      # The declarative `broadcasts_to` re-renders _message inside Turbo's
      # broadcast job (no request), where the reloaded message's belongs_to
      # reads — conversation.channel?, sender.channel_handle — hit the default
      # :all strict-loading mode: development LOGS the violation, test and
      # production RAISE it, so the message saved (200) but never appeared for
      # anyone. Reload with those associations and strict loading off first.
      # `targets:` (a CSS selector), not `target:` (one dom id): the corner chat
      # widget lives in the layout, so a channel page has two logs — a selector
      # appends to every open .conversation-log rather than whichever came first.
      after_create_commit :broadcast_to_logs
      # An edit replaces the line in every open thread; unsend! does the same by
      # hand, because update_columns runs no callbacks.
      after_update_commit :broadcast_change_to_logs, if: :saved_change_to_content?
      # Each reader's inbox row, rail row and badge (InboxBroadcastJob).
      after_create_commit { InboxBroadcastJob.perform_later(conversation_id, moved: true) }
    end

    private

    def broadcast_to_logs
      fresh = reloaded_for_render
      fresh.broadcast_append_to(
        fresh.conversation,
        targets: ".conversation-log",
        partial: "messages/message",
        locals: { message: fresh, broadcast: true },
      )
    end

    # `targets:` with the dom id as a selector, for the same reason as the
    # append: a channel page can hold the line twice, in the page and in the
    # corner widget.
    def broadcast_change_to_logs
      fresh = reloaded_for_render
      fresh.broadcast_replace_to(
        fresh.conversation,
        targets: "##{ActionView::RecordIdentifier.dom_id(fresh)}",
        partial: "messages/message",
        locals: { message: fresh, broadcast: true },
      )
      # An edit or an unsend of the newest line changes every reader's preview.
      InboxBroadcastJob.perform_later(conversation_id)
    end

    def reloaded_for_render
      Message.strict_loading(false).includes(:sender, :conversation, :link_preview, :reactions,
                                              :message_receipts).with_attached_attachment.find(id)
    end
  end
end
