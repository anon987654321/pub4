# frozen_string_literal: true

require "digest"
require "json"
require "time"

class Master::Review::CopyReview
  VERSION = 1
  DEFAULT_MAX_AGE_SECONDS = 7 * 24 * 60 * 60
  PRODUCT_FIELDS = %i[
    source external_id title merchant program_id price_cents currency
    category market in_stock placeholder last_seen_at
  ].freeze
  SOURCES = %w[tradedoubler amazon].freeze

  Finding = Data.define(:code, :status, :message, :claim, :evidence, :suggestion, :confidence) do
    def to_h
      { code:, status:, message:, claim:, evidence:, suggestion:, confidence: }.compact
    end
  end

  Report = Data.define(:status, :findings, :evidence, :summary, :version) do
    def pass? = status == :pass
    def fail? = status == :fail
    def inconclusive? = status == :inconclusive

    def to_h
      { status:, findings: findings.map(&:to_h), evidence:, summary:, version: }
    end
  end

  PRICE_TOKEN = /(?<![\p{Alnum}])(?:(NOK|SEK|DKK|EUR|USD|GBP|kr\.?|€|\$|£)\s*)?(\d{1,6}(?:[.,]\d{2})?)(?:\s*(NOK|SEK|DKK|EUR|USD|GBP|kr\.?|€|\$|£))?(?![\p{Alnum}])/iu
  DISCLOSURE_TERMS = {
    "en" => /\b(?:advertisement|sponsored|affiliate(?:\s+link)?|paid partnership)\b/i,
    "nb" => /\b(?:annonse|reklame|annonselenke|reklamelenke|affiliate(?:lenke|link)?)\b/i,
  }.freeze
  MARKET_CURRENCIES = { "NO" => "NOK", "SE" => "SEK", "DK" => "DKK" }.freeze

  def self.review(**arguments) = new(**arguments).review

  def initialize(creative:, product:, market: nil, now: Time.now.utc,
                 max_age_seconds: DEFAULT_MAX_AGE_SECONDS)
    @creative = creative
    @product = product
    @market = blank?(market) ? nil : market.to_s.upcase
    @now = coerce_time(now) || raise(ArgumentError, "now must be a Time or parseable timestamp")
    @max_age_seconds = Integer(max_age_seconds)
    raise ArgumentError, "max_age_seconds must be non-negative" if @max_age_seconds.negative?

    @findings = []
  end

  def review
    assess_copy_structure
    product_state = assess_product
    assess_disclosure(product_state)
    assess_claim_ledger(product_state)
    assess_unledgered_prices
    build_report(product_state)
  end

  private

  def assess_copy_structure
    if blank?(read(@creative, :headline))
      add(:headline_missing, :fail, "A creative headline is required.",
          suggestion: "Add a specific headline without inventing a product claim.")
    else
      add(:headline_present, :pass, "A headline is present.", confidence: 1.0)
    end

    if blank?(read(@creative, :cta))
      add(:cta_missing, :fail, "A call to action is missing.",
          suggestion: "Add a clear action that matches the destination.")
    else
      add(:cta_present, :pass, "A call to action is present.", confidence: 1.0)
    end

    locale = read(@creative, :locale)
    if locale_family(locale).nil?
      add(:locale_unresolved, :inconclusive,
          "The locale is missing or is outside the reviewed English/Bokmål set.",
          evidence: { locale: locale },
          suggestion: "Declare en, en-US, nb or nb-NO.")
    else
      add(:locale_declared, :pass, "A supported copy locale is declared.",
          evidence: { locale: locale.to_s }, confidence: 1.0)
    end
  end

  def assess_product
    unless @product
      add(:product_snapshot_missing, :inconclusive,
          "No persisted product snapshot was supplied; product claims cannot be checked.")
      return nil
    end

    source = read(@product, :source).to_s.downcase
    external_id = read(@product, :external_id)
    if !SOURCES.include?(source)
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

    case read(@product, :placeholder)
    when true
      add(:placeholder_inventory, :fail,
          "Placeholder inventory cannot support a live commercial claim.",
          suggestion: "Import a real product before publishing.")
    when false
      add(:real_inventory, :pass, "The product is not marked as a placeholder.", confidence: 1.0)
    else
      add(:placeholder_state_unknown, :inconclusive, "The placeholder state is not known.")
    end

    case read(@product, :in_stock)
    when true
      add(:product_in_stock, :pass, "The feed marks the product in stock.", confidence: 1.0)
    when false
      add(:product_out_of_stock, :fail,
          "The product is currently marked out of stock.",
          suggestion: "Do not advertise this product as available.")
    else
      add(:stock_state_unknown, :inconclusive, "The product stock state is not known.")
    end

    assess_freshness
    assess_market
    {
      source:,
      external_id: external_id&.to_s,
      price_cents: read(@product, :price_cents),
      currency: read(@product, :currency)&.to_s&.upcase,
      in_stock: read(@product, :in_stock),
      market: read(@product, :market)&.to_s&.upcase,
      last_seen_at: iso8601(read(@product, :last_seen_at)),
    }
  end

  def assess_freshness
    seen_at = coerce_time(read(@product, :last_seen_at))
    if seen_at.nil?
      add(:inventory_freshness_missing, :fail,
          "The product has no usable last_seen_at timestamp.",
          suggestion: "Refresh the feed; a missing timestamp is stale in the inventory contract.")
      return
    end

    age = @now - seen_at
    if age.negative? && age.abs > 300
      add(:inventory_timestamp_future, :inconclusive,
          "The product timestamp is more than five minutes in the future.",
          evidence: { last_seen_at: seen_at.iso8601 })
    elsif age > @max_age_seconds
      add(:inventory_stale, :fail,
          "The product is older than the #{@max_age_seconds}-second freshness window.",
          evidence: { last_seen_at: seen_at.iso8601, age_seconds: age.to_i },
          suggestion: "Refresh the feed or omit the product.")
    else
      add(:inventory_fresh, :pass, "The product is within the freshness window.",
          evidence: { last_seen_at: seen_at.iso8601, age_seconds: age.to_i }, confidence: 1.0)
    end
  end

  def assess_market
    return unless @market

    product_market = read(@product, :market).to_s.upcase
    if product_market.empty?
      add(:market_global, :pass, "The product has no market restriction.",
          evidence: { requested_market: @market }, confidence: 1.0)
    elsif product_market == @market
      add(:market_match, :pass, "The product market matches the requested market.",
          evidence: { market: @market }, confidence: 1.0)
    else
      add(:market_mismatch, :fail,
          "The product market does not match the requested publishing market.",
          evidence: { product_market:, requested_market: @market },
          suggestion: "Use inventory licensed for the publishing market.")
    end
  end

  def assess_disclosure(product_state)
    return unless product_state && SOURCES.include?(product_state[:source])

    disclosure = read(@creative, :disclosure)
    if blank?(disclosure)
      add(:affiliate_disclosure_missing, :fail,
          "Affiliate copy is missing its explicit commercial disclosure.",
          suggestion: "Add a translated affiliate/sponsored disclosure. Visual prominence is assessed separately.")
      return
    end

    family = locale_family(read(@creative, :locale))
    terms = family ? DISCLOSURE_TERMS[family] : Regexp.union(DISCLOSURE_TERMS.values)
    unless terms.match?(disclosure.to_s)
      add(:affiliate_disclosure_unrecognised, :fail,
          "The disclosure has no recognised commercial label for the declared locale.",
          evidence: { locale: read(@creative, :locale).to_s },
          suggestion: "Use an explicit Advertisement/Sponsored or Annonse/Reklame label.")
      return
    end

    add(:affiliate_disclosure_present, :pass,
        "An explicit affiliate/sponsored disclosure is present in the supplied copy.",
        evidence: { disclosure: disclosure.to_s }, confidence: 1.0)
  end

  def assess_claim_ledger(product_state)
    claims = read(@creative, :claims)
    if claims.nil?
      add(:claim_ledger_missing, :inconclusive,
          "No claim ledger was supplied; copy completeness cannot be established from text alone.",
          suggestion: "Supply a claims array, including an explicit empty array when there are no factual claims.")
      return
    end
    unless claims.is_a?(Array)
      add(:claim_ledger_invalid, :fail, "The claims field must be an array of structured claim records.")
      return
    end

    add(:claim_ledger_declared, :pass, "A structured claim ledger was supplied.",
        evidence: { claim_count: claims.length }, confidence: 1.0)

    claims.each_with_index do |claim, index|
      unless claim.is_a?(Hash)
        add(:claim_record_invalid, :fail, "Claim record #{index + 1} is not an object.", evidence: { index: })
        next
      end

      kind = read(claim, :kind).to_s.downcase
      text = read(claim, :text).to_s.strip
      if kind.empty? || text.empty?
        add(:claim_record_incomplete, :fail,
            "Claim record #{index + 1} needs both kind and text.", evidence: { index: })
        next
      end
      unless copy_contains?(text)
        add(:claim_not_in_copy, :inconclusive,
            "Claim record #{index + 1} was not found in the supplied headline, body or CTA.",
            claim: text, evidence: { index:, kind: })
        next
      end

      assess_claim(kind:, text:, index:)
    end
  end

  def assess_claim(kind:, text:, index:)
    case kind
    when "product_title", "merchant", "category"
      expected = read(@product, kind.to_sym).to_s.strip
      if expected.empty?
        add(:claim_field_missing, :inconclusive,
            "The product record has no #{kind} value to support this claim.",
            claim: text, evidence: { kind:, index: })
      elsif normalize_phrase(text) != normalize_phrase(expected)
        add(:claim_value_mismatch, :fail,
            "The #{kind} claim does not exactly match the current product record.",
            claim: text, evidence: { kind:, index:, source_value: expected },
            suggestion: "Use the exact feed value or remove the claim.")
      else
        add(:claim_field_verified, :pass,
            "The #{kind} claim matches the current product record.",
            claim: text, evidence: { kind:, index:, source_field: kind }, confidence: 1.0)
      end
    when "price"
      assess_price_claim(text:, index:)
    when "availability"
      assess_availability_claim(text:, index:)
    else
      claim = claim_at(index)
      add(:external_claim_unverified, :inconclusive,
          "Claim kind '#{kind}' requires external or human-reviewed evidence.",
          claim: text,
          evidence: { kind:, reference: read(claim, :reference) || read(claim, :source_reference) },
          suggestion: "Inspect the cited source; a reference string alone is not verification.")
    end
  end

  def assess_price_claim(text:, index:)
    cents = read(@product, :price_cents)
    currency = read(@product, :currency).to_s.upcase
    unless cents.is_a?(Integer) && !currency.empty?
      add(:price_source_missing, :inconclusive,
          "No integer minor-unit price and currency are available.",
          claim: text, evidence: { index: })
      return
    end

    expected = format("%d.%02d", cents / 100, cents.abs % 100)
    amount_ok = text.match?(/(?<!\d)#{Regexp.escape(expected)}(?!\d)/)
    currency_status = currency_marker_status(text, currency)
    if !amount_ok || currency_status == :mismatch
      add(:price_claim_mismatch, :fail,
          "The price claim does not state the feed's exact amount and currency.",
          claim: text, evidence: { index:, expected_amount: expected, expected_currency: currency },
          suggestion: "Render the current feed price and currency exactly.")
    elsif currency_status == :unknown
      add(:price_currency_unresolved, :inconclusive,
          "The currency marker is ambiguous for the product's market.",
          claim: text, evidence: { index:, expected_currency: currency },
          suggestion: "Use an explicit currency code such as NOK or EUR.")
    else
      add(:price_claim_verified, :pass,
          "The price claim matches the feed's integer minor-unit price and currency.",
          claim: text, evidence: { index:, price_cents: cents, currency: }, confidence: 1.0)
    end
  end

  def assess_availability_claim(text:, index:)
    stated = availability_phrase(text)
    stock = read(@product, :in_stock)
    if stated.nil?
      add(:availability_wording_unrecognised, :inconclusive,
          "Availability wording is outside the deterministic English/Bokmål phrase set.",
          claim: text, evidence: { index: })
    elsif stock.nil?
      add(:availability_source_missing, :inconclusive,
          "The feed has no stock value to verify this availability claim.",
          claim: text, evidence: { index: })
    elsif stated != stock
      add(:availability_claim_mismatch, :fail,
          "The availability claim contradicts the product feed's stock value.",
          claim: text, evidence: { index:, feed_in_stock: stock },
          suggestion: "Match the copy to the current stock state or omit the claim.")
    else
      add(:availability_claim_verified, :pass,
          "The availability wording agrees with the product feed.",
          claim: text, evidence: { index:, in_stock: stock }, confidence: 1.0)
    end
  end

  def assess_unledgered_prices
    text = copy_text
    return if text.empty?

    claims = read(@creative, :claims)
    kinds = Array(claims).select { |claim| claim.is_a?(Hash) }
                         .map { |claim| read(claim, :kind).to_s.downcase }

    price_tokens(text).each do |token|
      amount = token[:amount_cents]
      product_price = read(@product, :price_cents)
      currency = read(@product, :currency).to_s.upcase
      copy_currency = currency_for_marker(token[:marker], read(@product, :market))
      if product_price.is_a?(Integer) && amount && amount != product_price
        add(:price_amount_mismatch, :fail,
            "A currency-labelled amount in the copy differs from the feed price.",
            claim: token[:text], evidence: { product_price_cents: product_price, copy_amount_cents: amount })
      elsif product_price.is_a?(Integer) && copy_currency && copy_currency != currency
        add(:price_currency_mismatch, :fail,
            "A currency-labelled amount in the copy uses a different currency from the feed.",
            claim: token[:text], evidence: { product_currency: currency, copy_currency: })
      elsif product_price.is_a?(Integer) && copy_currency.nil?
        add(:price_currency_unresolved, :inconclusive,
            "The currency marker is ambiguous for the product market.",
            claim: token[:text], suggestion: "Use an explicit currency code.")
      elsif !kinds.include?("price")
        add(:price_claim_without_ledger, :inconclusive,
            "A currency-labelled amount appears in the copy but has no price claim record.",
            claim: token[:text], suggestion: "Add a price claim record or remove the amount.")
      end
    end
  end

  def price_tokens(text)
    text.scan(PRICE_TOKEN).filter_map do |prefix, amount, suffix|
      marker = prefix || suffix
      next unless marker

      { text: [marker, amount].join(" "), marker:, amount_cents: amount_to_cents(amount) }
    end
  end

  def amount_to_cents(value)
    return if value.to_s.count(".,") > 1

    whole, fraction = value.to_s.split(/[.,]/, 2)
    return unless whole.match?(/\A\d+\z/)

    (whole.to_i * 100) + (fraction || "0").ljust(2, "0").to_i
  end

  def currency_marker_status(text, expected)
    matches = text.scan(PRICE_TOKEN)
    return :unknown if matches.empty?

    marker = matches.first[0] || matches.first[2]
    actual = currency_for_marker(marker, read(@product, :market))
    return :unknown unless actual

    actual == expected ? :match : :mismatch
  end

  def currency_for_marker(marker, market)
    value = marker.to_s.upcase.delete(".")
    return value if %w[NOK SEK DKK EUR USD GBP].include?(value)
    return MARKET_CURRENCIES[market.to_s.upcase] if value == "KR"

    { "€" => "EUR", "£" => "GBP" }[value]
  end

  def availability_phrase(text)
    normalized = normalize_phrase(text)
    positive = %w[in stock available now pa lager tilgjengelig na].any? { |phrase| normalized.include?(phrase) }
    negative = %w[out of stock unavailable sold out utsolgt ikke pa lager].any? { |phrase| normalized.include?(phrase) }
    return nil if positive == negative

    positive
  end

  def claim_at(index) = Array(read(@creative, :claims))[index]

  def copy_contains?(phrase)
    normalized = normalize_phrase(phrase)
    !normalized.empty? && normalize_phrase(copy_text).include?(normalized)
  end

  def copy_text
    %i[headline body cta].filter_map do |key|
      value = read(@creative, key)
      value.to_s unless blank?(value)
    end.join(" ")
  end

  def build_report(product_state)
    counts = @findings.group_by(&:status).transform_values(&:size)
    status = if counts.fetch(:fail, 0).positive?
               :fail
             elsif counts.fetch(:inconclusive, 0).positive?
               :inconclusive
             else
               :pass
             end
    snapshot = product_snapshot
    evidence = {
      read_only: true,
      product: product_state,
      product_snapshot_sha256: snapshot && Digest::SHA256.hexdigest(JSON.generate(canonical(snapshot))),
      locale: read(@creative, :locale)&.to_s,
      claim_count: Array(read(@creative, :claims)).size,
      scope: "declared_copy_and_supported_feed_fields",
      limitations: [
        "Natural-language meaning and claim-ledger completeness are not independently proven.",
        "External references are not fetched; unsupported claims remain INCONCLUSIVE.",
        "Disclosure wording is checked here; rendered prominence and consent use separate controls."
      ],
    }
    Report.new(
      status:,
      findings: @findings.freeze,
      evidence: evidence.freeze,
      summary: {
        pass: counts.fetch(:pass, 0),
        fail: counts.fetch(:fail, 0),
        inconclusive: counts.fetch(:inconclusive, 0),
      }.freeze,
      version: VERSION,
    )
  end

  def product_snapshot
    return unless @product

    PRODUCT_FIELDS.to_h do |field|
      value = read(@product, field)
      value = value.iso8601 if value.respond_to?(:iso8601)
      [field, value]
    end
  end

  def add(code, status, message, claim: nil, evidence: nil, suggestion: nil, confidence: nil)
    @findings << Finding.new(
      code:, status:, message:, claim: claim&.to_s,
      evidence:, suggestion:, confidence:
    )
  end

  def read(record, key)
    return if record.nil?
    return record[key] if record.is_a?(Hash) && record.key?(key)
    return record[key.to_s] if record.is_a?(Hash) && record.key?(key.to_s)
    return record.public_send(key) if record.respond_to?(key)

    nil
  end

  def blank?(value) = value.nil? || value.to_s.strip.empty?

  def normalize_phrase(value)
    value.to_s.downcase.gsub(/[^\p{Alnum}]+/u, " ").strip
  end

  def locale_family(value)
    family = value.to_s.downcase.split(/[-_]/).first
    DISCLOSURE_TERMS.key?(family) ? family : nil
  end

  def coerce_time(value)
    return value if value.is_a?(Time)
    return value.to_time if value.respond_to?(:to_time)
    return Time.parse(value) if value.is_a?(String)

    nil
  rescue ArgumentError, RangeError
    nil
  end

  def iso8601(value) = coerce_time(value)&.utc&.iso8601

  def canonical(value)
    case value
    when Hash
      value.keys.sort_by(&:to_s).to_h { |key| [key.to_s, canonical(value.fetch(key))] }
    when Array
      value.map { |item| canonical(item) }
    else
      value
    end
  end
end
