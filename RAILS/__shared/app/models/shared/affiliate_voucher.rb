# frozen_string_literal: true

# A voucher / promotion from an affiliate network (TradeDoubler Vouchers API).
module Shared
  class AffiliateVoucher < ApplicationRecord
    # Namespaced into Shared when the affiliate stack moved out of brgen so
    # amber could use it too. The table is not: it predates the move and both
    # apps migrate it under its own name.
    self.table_name = "affiliate_vouchers"

    SOURCES = %w[tradedoubler].freeze
    # 1 voucher code, 2 discount, 3 free article, 4 free shipping, 5 raffle, 6 promotion
    TYPES = {
      1 => "voucher",
      2 => "discount",
      3 => "free_article",
      4 => "free_shipping",
      5 => "raffle",
      6 => "promotion",
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
        external_id:,
        program_id:,
        program_name:,
        code:,
        title:,
        short_description:,
        description:,
        voucher_type_id:,
        track_url:,
        landing_url:,
        discount_amount:,
        percentage:,
        site_specific:,
        exclusive:,
        currency:,
        starts_at:,
        ends_at:,
      )
    end

    def self.upsert_from_api!(voucher)
      record = find_or_initialize_by(source: "tradedoubler", external_id: voucher.external_id.to_s)
      record.assign_attributes(api_attributes(voucher))
      record.save!
      record
    end

    def self.api_attributes(voucher)
      program_attributes(voucher)
        .merge(description_attributes(voucher))
        .merge(offer_attributes(voucher))
        .merge(tracking_attributes(voucher))
    end

    def self.program_attributes(voucher)
      {
        program_id: fetch_any(voucher, :program_id),
        program_name: fetch_any(voucher, :program_name),
        code: fetch_any(voucher, :code),
      }
    end

    def self.description_attributes(voucher)
      {
        title: fetch_any(voucher, :title).presence || "Offer",
        short_description: fetch_any(voucher, :short_description),
        description: fetch_any(voucher, :description),
      }
    end

    def self.offer_attributes(voucher)
      {
        voucher_type_id: fetch_any(voucher, :voucher_type_id).positive? ? fetch_any(voucher, :voucher_type_id) : 1,
        discount_amount: fetch_any(voucher, :discount_amount),
        percentage: fetch_any(voucher, :percentage),
        site_specific: fetch_any(voucher, :site_specific),
        exclusive: fetch_any(voucher, :exclusive),
        currency: fetch_any(voucher, :currency),
        market: Tradedoubler.market,
      }
    end

    def self.tracking_attributes(voucher)
      {
        track_url: fetch_any(voucher, :track_url).presence ||
                   fetch_any(voucher, :landing_url).presence || "https://brgen.no",
        landing_url: fetch_any(voucher, :landing_url),
        starts_at: fetch_any(voucher, :starts_at),
        ends_at: fetch_any(voucher, :ends_at),
        last_seen_at: Time.current,
      }
    end

    def self.fetch_any(record, *attributes)
      attributes.each do |attribute|
        value = record.public_send(attribute)
        return value unless value.nil?
      end
      nil
    end

    private_class_method :api_attributes, :program_attributes, :description_attributes,
                         :offer_attributes, :tracking_attributes, :fetch_any
  end
end
