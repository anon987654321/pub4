# frozen_string_literal: true

class Takeaway::Order
  # One ticket, several people. The host is `user` — the person who opened it
  # and the only one who can send it to the kitchen — and every line knows who
  # added it.
  module GroupTicket
    extend ActiveSupport::Concern

    def open_group!
      update!(group_open: true, group_token: group_token.presence || SecureRandom.urlsafe_base64(12))
    end

    def group? = group_token.present?
    def host?(candidate) = candidate.present? && candidate.id == user_id

    # Anyone with the link may add to an open ticket that has not left yet. Once
    # it is confirmed the kitchen is cooking it, and a late line is a different
    # order rather than a surprise on this one.
    def joinable? = group? && group_open? && status == "pending"

    # What each person owes, so the ticket can be split without anybody doing
    # arithmetic in a chat. Delivery and tip stay the host's — splitting a fee
    # four ways to the øre is a worse argument than paying it.
    def shares
      order_items.group_by(&:user_id).transform_values { |items| items.sum(&:subtotal_cents) }
    end
  end
end
