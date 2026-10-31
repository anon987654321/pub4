# frozen_string_literal: true

require "digest"
require "json"
require "time"

class Master::Review::CopyReview::InventoryReview
  Result = Data.define(:product, :sha256, :findings)

  def initialize(product:, market:, now:, max_age_seconds:)
    @product = product
    @market = market
    @now = now
    @max_age_seconds = max_age_seconds
    @findings = []
  end

  def review
    return missing_product_result unless @product

    assess_inventory
    Result.new(product: product_state, sha256: product_digest, findings: @findings.freeze)
  end

  def self.coerce_time(value)
    return value if value.is_a?(Time)
    return value.to_time if value.respond_to?(:to_time)
    return Time.parse(value) if value.is_a?(String)

    nil
  rescue ArgumentError, RangeError
    nil
  end

  private

  def missing_product_result
    add(:product_snapshot_missing, :inconclusive,
        "No persisted product snapshot was supplied; product claims cannot be checked.")
    Result.new(product: nil, sha256: nil, findings: @findings.freeze)
  end

  def assess_inventory
    assess_identity
    assess_placeholder
    assess_stock
    assess_freshness
    assess_market
  end

  def product_state
    {
      source: read(:source).to_s.downcase,
      external_id: read(:external_id)&.to_s,
      price_cents: read(:price_cents),
      currency: read(:currency)&.to_s&.upcase,
      in_stock: read(:in_stock),
      market: read(:market)&.to_s&.upcase,
      last_seen_at: iso8601(read(:last_seen_at)),
    }.freeze
  end

  def product_digest
    snapshot = product_snapshot
    ordered = snapshot.sort_by { |key, _value| key.to_s }.to_h
    Digest::SHA256.hexdigest(JSON.generate(ordered))
  end

  def product_snapshot
    Master::Review::CopyReview::PRODUCT_FIELDS.to_h do |field|
      value = read(field)
      value = iso8601(value) if value.respond_to?(:iso8601)
      [field, value]
    end
  end

  def assess_identity
    source = read(:source).to_s.downcase
    external_id = read(:external_id)
    if !Master::Review::CopyReview::SOURCES.include?(source)
      add(:product_source_unknown, :fail,
          "The product source is missing or unsupported.", evidence: { source: })
    elsif blank?(external_id)
      add(:product_identity_missing, :inconclusive,
          "The product has no stable external product identifier.", evidence: { source: })
    else
      add(:product_identity_present, :pass,
          "The product has a supported source and stable external ID.",
          evidence: { source:, external_id: external_id.to_s }, confidence: 1.0)
    end
  end

  def assess_placeholder
    case read(:placeholder)
    when true
      add(:placeholder_inventory, :fail,
          "Placeholder inventory cannot support a live commercial claim.",
          suggestion: "Import a real product before publishing.")
    when false
      add(:real_inventory, :pass, "The product is not marked as a placeholder.", confidence: 1.0)
    else
      add(:placeholder_state_unknown, :inconclusive, "The placeholder state is not known.")
    end
  end

  def assess_stock
    case read(:in_stock)
    when true
      add(:product_in_stock, :pass, "The feed marks the product in stock.", confidence: 1.0)
    when false
      add(:product_out_of_stock, :fail,
          "The product is currently marked out of stock.",
          suggestion: "Do not advertise this product as available.")
    else
      add(:stock_state_unknown, :inconclusive, "The product stock state is not known.")
    end
  end

  def assess_freshness
    seen_at = self.class.coerce_time(read(:last_seen_at))
    return freshness_missing unless seen_at

    age = @now - seen_at
    return freshness_future(seen_at) if age.negative? && age.abs > 300
    return freshness_stale(seen_at, age) if age > @max_age_seconds

    freshness_current(seen_at, age)
  end

  def freshness_missing
    add(:inventory_freshness_missing, :fail,
        "The product has no usable last_seen_at timestamp.",
        suggestion: "Refresh the feed; a missing timestamp is stale in the inventory contract.")
  end

  def freshness_future(seen_at)
    add(:inventory_timestamp_future, :inconclusive,
        "The product timestamp is more than five minutes in the future.",
        evidence: { last_seen_at: seen_at.iso8601 })
  end

  def freshness_stale(seen_at, age)
    add(:inventory_stale, :fail,
        "The product is older than the #{@max_age_seconds}-second freshness window.",
        evidence: { last_seen_at: seen_at.iso8601, age_seconds: age.to_i },
        suggestion: "Refresh the feed or omit the product.")
  end

  def freshness_current(seen_at, age)
    add(:inventory_fresh, :pass, "The product is within the freshness window.",
        evidence: { last_seen_at: seen_at.iso8601, age_seconds: age.to_i }, confidence: 1.0)
  end

  def assess_market
    return unless @market

    product_market = read(:market).to_s.upcase
    return market_global if product_market.empty?
    return market_match if product_market == @market

    market_mismatch(product_market)
  end

  def market_global
    add(:market_global, :pass, "The product has no market restriction.",
        evidence: { requested_market: @market }, confidence: 1.0)
  end

  def market_match
    add(:market_match, :pass, "The product market matches the requested market.",
        evidence: { market: @market }, confidence: 1.0)
  end

  def market_mismatch(product_market)
    add(:market_mismatch, :fail,
        "The product market does not match the requested publishing market.",
        evidence: { product_market:, requested_market: @market },
        suggestion: "Use inventory licensed for the publishing market.")
  end

  def add(code, status, message, evidence: nil, suggestion: nil, confidence: nil)
    @findings << Master::Review::CopyReview::Finding.new(
      code:, status:, message:, claim: nil, evidence:, suggestion:, confidence:
    )
  end

  def read(key)
    return @product[key] if @product.is_a?(Hash) && @product.key?(key)
    return @product[key.to_s] if @product.is_a?(Hash) && @product.key?(key.to_s)
    return @product.public_send(key) if @product.respond_to?(key)

    nil
  end

  def blank?(value) = value.nil? || value.to_s.strip.empty?
  def iso8601(value) = self.class.coerce_time(value)&.utc&.iso8601
end
