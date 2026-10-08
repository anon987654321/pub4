# frozen_string_literal: true

# An evening's work: a fee, a start, and how long it runs.
class Marketplace::GigDetail < ApplicationRecord
  belongs_to :listing, class_name: "Marketplace::Listing"

  validates :pay_cents, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :hours, numericality: { greater_than: 0 }, allow_nil: true
  validate :starts_in_the_future, on: :create

  def pay_display = pay_cents.present? ? Shared::MoneyDisplay.format(pay_cents) : nil

  private

  # A gig in the past is not an offer. On create only: one that has since
  # happened is a record, and editing its title should not be refused because
  # time passed.
  def starts_in_the_future
    return if starts_at.blank? || starts_at >= Time.current

    errors.add(:starts_at, :in_the_past)
  end
end
