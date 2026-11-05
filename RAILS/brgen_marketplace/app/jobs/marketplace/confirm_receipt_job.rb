# frozen_string_literal: true

module Marketplace
  # Confirms receipt for paid orders the seller marked delivered longer than
  # Order::RECEIPT_WINDOW ago, where the buyer neither confirmed nor opened a
  # return. Confirmation is what creates a shop's payout, so a buyer who never
  # answers does not hold the seller's money forever, and the seller's word
  # alone never moves it.
  class ConfirmReceiptJob < ApplicationJob
    queue_as :bulk

    def perform
      Marketplace::Order.strict_loading(false).receipt_overdue.find_each(&:mark_delivered!)
    end
  end
end
