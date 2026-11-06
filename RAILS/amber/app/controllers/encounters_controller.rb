# frozen_string_literal: true

# Chatroulette-style random pairing. A stranger chat needs both sides to ask
# for a stranger, so guests play without an account - the ask is the consent.
class EncountersController < ApplicationController
  before_action :require_user_session

  # Anonymous stranger chat is abuse-prone - cap how fast encounters start,
  # the same rule NearbyController applies to brgen's stranger chats.
  rate_limit to: 10, within: 5.minutes, only: :create,
    with: -> { redirect_to root_path, alert: t("flash.encounters_rate_limited") }

  def create
    mine = Encounter.pair!(ensure_guest_user!)
    if mine.matched?
      redirect_to messages_path(with: mine.partner_id)
    else
      redirect_to waiting_encounters_path
    end
  end

  # The waiting page leans on the shared morph refresh: every couple of
  # seconds the refresh visit lands here, and the moment the pairing exists
  # the visit follows the redirect into the thread.
  def waiting
    matched = Current.user.encounters.matched.order(:updated_at).last
    if matched&.partner && matched.fresh?
      matched.close!
      redirect_to messages_path(with: matched.partner_id)
      return
    end

    # Re-arm a lapsed wait so a stranger arriving later can still pair.
    Current.user.encounters.waiting.first_or_create! unless Current.user.encounters.waiting.exists?
    render :waiting
  end

  def destroy
    Current.user.encounters.waiting.update_all(status: Encounter::CLOSED)
    redirect_to root_path, notice: t("flash.encounter_left")
  end
end
