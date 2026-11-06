# frozen_string_literal: true

# Chatroulette-style random pairing on the ambient-chat machinery. A stranger
# chat needs both sides to ask for a stranger, so guests play without an
# account - the ask is the consent, the same Craigslist shape the geo rooms use.
class EncountersController < ApplicationController
  # Anonymous stranger chat is abuse-prone - cap how fast encounters start,
  # the same rule nearby applies to its stranger chats.
  rate_limit to: 10, within: 5.minutes, only: :create,
    with: -> { redirect_to nearby_path, alert: t("flash.encounters_rate_limited") }

  def create
    me = ensure_guest_user!
    blocked = me.blocked_user_ids + Block.where(blocked_id: me.id).pluck(:blocker_id)
    mine = Encounter.pair!(me, blocked_ids: blocked.uniq)
    if mine.matched?
      redirect_to mine.conversation
    else
      redirect_to waiting_encounters_path
    end
  end

  # The waiting page leans on the shared morph refresh: every couple of
  # seconds the refresh visit lands here, and the moment the pairing exists
  # the visit follows the redirect into the conversation.
  def waiting
    matched = Current.user.encounters.matched.order(:updated_at).last
    if matched&.conversation && matched.fresh?
      matched.close!
      redirect_to matched.conversation
      return
    end

    # Re-arm a lapsed wait so a stranger arriving later can still pair.
    Current.user.encounters.waiting.first_or_create! unless Current.user.encounters.waiting.exists?
    render :waiting
  end

  def destroy
    Current.user.encounters.waiting.update_all(status: Encounter::CLOSED)
    redirect_to nearby_path, notice: t("flash.encounter_left")
  end
end
