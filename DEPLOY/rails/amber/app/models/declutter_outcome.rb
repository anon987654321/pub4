# frozen_string_literal: true

class DeclutterOutcome < ApplicationRecord
  include MoneyInOre
  money_reader :amount_recovered

  belongs_to :user
  belongs_to :item

  ACTIONS = %w[sold donated gifted recycled repaired archived released].freeze

  validates :action, inclusion: { in: ACTIONS }
  validates :notes, length: { maximum: 1_000 }
  validates :amount_recovered_cents, numericality: { greater_than_or_equal_to: 0, only_integer: true }, allow_nil: true

  before_validation :assign_user
  after_create :sync_item_lifecycle

  private

  def assign_user
    self.user ||= item&.user
  end

  def sync_item_lifecycle
    state = case action
    when "sold" then "sold"
    when "donated" then "donated"
    when "gifted", "released" then "released"
    when "recycled" then "recycled"
    when "repaired" then "active"
    when "archived" then "sentimental_archive"
    else item.lifecycle_state
    end
    item.update!(lifecycle_state: state)
  end
end
