# frozen_string_literal: true

# A voucher / promotion from an affiliate network (TradeDoubler Vouchers API).
class AffiliateVoucher < ApplicationRecord
  SOURCES = %w[tradedoubler].freeze
  # 1 voucher code, 2 discount, 3 free article, 4 free shipping, 5 raffle, 6 promotion
  TYPES = {
    1 => "voucher",
    2 => "discount",
    3 => "free_article",
    4 => "free_shipping",
    5 => "raffle",
    6 => "promotion"
  }.freeze

  validates :source, presence: true, inclusion: { in: SOURCES }
  validates :external_id, presence: true, uniqueness: { scope: :source }
  validates :title, presence: true, length: { maximum: 120 }
  validates :track_url, presence: true, length: { maximum: 2_000 }
  validates :voucher_type_id, inclusion: { in: TYPES.keys }

  scope :live, lambda {
    now = Time.current
    where("(starts_at IS NULL OR starts_at <= ?) AND (ends_at IS NULL OR ends_at >= ?)", now, now)
  }
  scope :exclusive_or_site, -> { where(site_specific: true).or(where(exclusive: true)) }
  scope :for_market, ->(market) { where(market: [ market.to_s.upcase, nil ]) if market.present? }

  def type_name = TYPES[voucher_type_id] || "unknown"

  def to_struct
    Tradedoubler::Voucher.new(
      external_id: external_id,
      program_id: program_id,
      program_name: program_name,
      code: code,
      title: title,
      short_description: short_description,
      description: description,
      voucher_type_id: voucher_type_id,
      track_url: track_url,
      landing_url: landing_url,
      discount_amount: discount_amount,
      percentage: percentage,
      site_specific: site_specific,
      exclusive: exclusive,
      currency: currency,
      starts_at: starts_at,
      ends_at: ends_at
    )
  end

  def self.upsert_from_api!(voucher)
    record = find_or_initialize_by(source: "tradedoubler", external_id: voucher.external_id.to_s)
    record.assign_attributes(
      program_id: voucher.program_id,
      program_name: voucher.program_name,
      code: voucher.code,
      title: voucher.title.presence || "Offer",
      short_description: voucher.short_description,
      description: voucher.description,
      voucher_type_id: voucher.voucher_type_id.positive? ? voucher.voucher_type_id : 1,
      track_url: voucher.track_url.presence || voucher.landing_url.presence || "https://brgen.no",
      landing_url: voucher.landing_url,
      discount_amount: voucher.discount_amount,
      percentage: voucher.percentage,
      site_specific: voucher.site_specific,
      exclusive: voucher.exclusive,
      currency: voucher.currency,
      market: Tradedoubler.market,
      starts_at: voucher.starts_at,
      ends_at: voucher.ends_at,
      last_seen_at: Time.current
    )
    record.save!
    record
  end
end
