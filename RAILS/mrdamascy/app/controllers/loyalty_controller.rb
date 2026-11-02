# frozen_string_literal: true

class LoyaltyController < ApplicationController
  STAMP_SLOTS = 10

  # Sahtein-kortet (APP_SPEC §6): ten 8-point star slots, filled for every
  # unredeemed stamp; progress text + how-it-works in the view/locales.
  def show
    @stamp_slots = STAMP_SLOTS
    @unredeemed = current_user ? current_user.unredeemed_stamp_count : 0
    @earned = current_user ? current_user.stamp_count : 0
    @free_wrap_ready = current_user&.free_wrap_ready? || false
  end
end
