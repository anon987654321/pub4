# frozen_string_literal: true

# "Message me" — one link a person can send to somebody who has no account here.
#
# The whole on-ramp is this: tap the link, sign in with Vipps, land in a
# conversation with the person who sent it. WhatsApp's equivalent is a phone
# number, which works because everyone already has one; a Vipps sign-in is the
# same shape and proves a real person without harvesting an address book.
#
# The token is a Rails signed_id, so nothing is stored: no invites table, no
# cleanup job, and a link cannot be guessed or edited into somebody else's. It
# expires, because a link shared once tends to outlive the reason for it.
class InvitesController < ApplicationController
  allow_unauthenticated_access

  PURPOSE = :message_invite
  TTL = 30.days

  def show
    host = User.find_signed(params[:token], purpose: PURPOSE)
    return redirect_to(root_path, alert: t("invite.expired")) if host.nil?
# Deliberately not User.messageable. That scope answers "who may appear in the
# people picker", and it excludes guests because a guest has no identity you
# could search for later. Being handed a link is the opposite situation: the
# person chose to give it to you, so there is nothing to find and nothing to
# guess. Requiring both conflated a search permission with a share.
#
# What still disqualifies a host is being gone: a deleted account, or one on
# its way out, should not open new threads.
return redirect_to(root_path, alert: t("invite.expired")) if host.deleted_at.present?
return redirect_to(root_path, alert: t("invite.expired")) if host.deletion_scheduled_at.present?

    # Not signed in yet: keep the token, not the resolved user, so the thing held
    # over the sign-in round trip is the same thing that arrived — and expires on
    # its own schedule rather than living in a session forever.
    unless Current.user
      session[:invite_token] = params[:token]
      return redirect_to sign_in_path, notice: t("invite.sign_in_to_reply", name: host.display_name)
    end

    redirect_to conversation_for(host)
  end

  private

  def conversation_for(host)
    # Your own link is not an error worth a message — you were probably testing
    # it — so it simply takes you to your inbox.
    return conversations_path if host.id == Current.user.id

    Conversation.find_or_create_direct(Current.user, host)
  end
end
