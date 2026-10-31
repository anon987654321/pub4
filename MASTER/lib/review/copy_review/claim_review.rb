# frozen_string_literal: true

class Master::Review::CopyReview::ClaimReview
  Result = Data.define(:findings)
  PRICE_TOKEN = /(?<![\p{Alnum}])(?:(NOK|SEK|DKK|EUR|USD|GBP|kr\.?|€|\$|£)\s*)?(\d{1,6}(?:[.,]\d{2})?)(?:\s*(NOK|SEK|DKK|EUR|USD|GBP|kr\.?|€|\$|£))?(?![\p{Alnum}])/iu
  MARKET_CURRENCIES = { "NO" => "NOK", "SE" => "SEK", "DK" => "DKK" }.freeze

  def initialize(creative:, product:)
    @creative = creative
    @product = product
    @findings = []
  end

  def review
    assess_claim_ledger
    assess_unledgered_prices
    Result.new(findings: @findings.freeze)
  end

  private

  def assess_claim_ledger
    claims = read(@creative, :claims)
    return missing_ledger if claims.nil?
    return invalid_ledger unless claims.is_a?(Array)

    add(:claim_ledger_declared, :pass, "A structured claim ledger was supplied.",
        evidence: { claim_count: claims.length }, confidence: 1.0)
    claims.each_with_index { |claim, index| assess_claim(claim, index) }
  end

  def missing_ledger
    add(:claim_ledger_missing, :inconclusive,
        "No claim ledger was supplied; copy completeness cannot be established from text alone.",
        suggestion: "Supply a claims array, including an explicit empty array when there are no factual claims.")
  end

  def invalid_ledger
    add(:claim_ledger_invalid, :fail, "The claims field must be an array of structured claim records.")
  end

  def assess_claim(claim, index)
    return invalid_record(index) unless claim.is_a?(Hash)

    kind = read(claim, :kind).to_s.downcase
    text = read(claim, :text).to_s.strip
    return incomplete_record(index) if kind.empty? || text.empty?
    return missing_copy_claim(kind, text, index) unless copy_contains?(text)

    assess_claim_kind(kind, text, index, claim)
  end

  def invalid_record(index)
    add(:claim_record_invalid, :fail, "Claim record #{index + 1} is not an object.", evidence: { index: })
  end

  def incomplete_record(index)
    add(:claim_record_incomplete, :fail,
        "Claim record #{index + 1} needs both kind and text.", evidence: { index: })
  end

  def missing_copy_claim(kind, text, index)
    add(:claim_not_in_copy, :inconclusive,
        "Claim record #{index + 1} was not found in the supplied headline, body or CTA.",
        claim: text, evidence: { index:, kind: })
  end

  def assess_claim_kind(kind, text, index, claim)
    case kind
    when "product_title", "merchant", "category" then assess_text_field(kind, text, index)
    when "price" then assess_price(text, index)
    when "availability" then assess_availability(text, index)
    else assess_external_claim(kind, text, claim)
    end
  end

  def assess_external_claim(kind, text, claim)
    add(:external_claim_unverified, :inconclusive,
        "Claim kind '#{kind}' requires external or human-reviewed evidence.",
        claim: text,
        evidence: { kind:, reference: read(claim, :reference) || read(claim, :source_reference) },
        suggestion: "Inspect the cited source; a reference string alone is not verification.")
  end

  def assess_text_field(kind, text, index)
    expected = read(@product, kind.to_sym).to_s.strip
    return missing_field(kind, text, index) if expected.empty?
    return mismatched_field(kind, text, index, expected) unless normalize(text) == normalize(expected)

    add(:claim_field_verified, :pass, "The #{kind} claim matches the current product record.",
        claim: text, evidence: { kind:, index:, source_field: kind }, confidence: 1.0)
  end

  def missing_field(kind, text, index)
    add(:claim_field_missing, :inconclusive,
        "The product record has no #{kind} value to support this claim.",
        claim: text, evidence: { kind:, index: })
  end

  def mismatched_field(kind, text, index, expected)
    add(:claim_value_mismatch, :fail,
        "The #{kind} claim does not exactly match the current product record.",
        claim: text, evidence: { kind:, index:, source_value: expected },
        suggestion: "Use the exact feed value or remove the claim.")
  end

  def assess_price(text, index)
    cents = read(@product, :price_cents)
    currency = read(@product, :currency).to_s.upcase
    return missing_price_source(text, index) unless cents.is_a?(Integer) && !currency.empty?

    expected = format("%d.%02d", cents / 100, cents.abs % 100)
    amount_ok = text.match?(/(?<!\d)#{Regexp.escape(expected)}(?!\d)/)
    marker = marker_status(text, currency)
    return mismatched_price(text, index, expected, currency) if !amount_ok || marker == :mismatch
    return unknown_price_currency(text, index, currency) if marker == :unknown

    add(:price_claim_verified, :pass, "The price claim matches the feed's integer minor-unit price and currency.",
        claim: text, evidence: { index:, price_cents: cents, currency: }, confidence: 1.0)
  end

  def missing_price_source(text, index)
    add(:price_source_missing, :inconclusive,
        "No integer minor-unit price and currency are available.",
        claim: text, evidence: { index: })
  end

  def mismatched_price(text, index, expected, currency)
    add(:price_claim_mismatch, :fail,
        "The price claim does not state the feed's exact amount and currency.",
        claim: text, evidence: { index:, expected_amount: expected, expected_currency: currency },
        suggestion: "Render the current feed price and currency exactly.")
  end

  def unknown_price_currency(text, index, currency)
    add(:price_currency_unresolved, :inconclusive,
        "The currency marker is ambiguous for the product's market.",
        claim: text, evidence: { index:, expected_currency: currency },
        suggestion: "Use an explicit currency code such as NOK or EUR.")
  end

  def assess_availability(text, index)
    stated = availability_phrase(text)
    stock = read(@product, :in_stock)
    return unrecognised_availability(text, index) if stated.nil?
    return missing_availability(text, index) if stock.nil?
    return mismatched_availability(text, index, stock) if stated != stock

    add(:availability_claim_verified, :pass, "The availability wording agrees with the product feed.",
        claim: text, evidence: { index:, in_stock: stock }, confidence: 1.0)
  end

  def unrecognised_availability(text, index)
    add(:availability_wording_unrecognised, :inconclusive,
        "Availability wording is outside the deterministic English/Bokmål phrase set.",
        claim: text, evidence: { index: })
  end

  def missing_availability(text, index)
    add(:availability_source_missing, :inconclusive,
        "The feed has no stock value to verify this availability claim.",
        claim: text, evidence: { index: })
  end

  def mismatched_availability(text, index, stock)
    add(:availability_claim_mismatch, :fail,
        "The availability claim contradicts the product feed's stock value.",
        claim: text, evidence: { index:, feed_in_stock: stock },
        suggestion: "Match the copy to the current stock state or omit the claim.")
  end

  def assess_unledgered_prices
    declared = Array(read(@creative, :claims)).any? do |claim|
      claim.is_a?(Hash) && read(claim, :kind).to_s.downcase == "price"
    end
    price_tokens(copy_text).each { |token| assess_unledgered_price(token, declared) }
  end

  def assess_unledgered_price(token, declared)
    amount = token[:amount_cents]
    product_price = read(@product, :price_cents)
    currency = read(@product, :currency).to_s.upcase
    copy_currency = currency_for_marker(token[:marker], read(@product, :market))
    return amount_mismatch(token, product_price, amount) if product_price.is_a?(Integer) && amount && amount != product_price
    return currency_mismatch(token, currency, copy_currency) if product_price.is_a?(Integer) && copy_currency && copy_currency != currency
    return currency_unknown(token) if product_price.is_a?(Integer) && copy_currency.nil?
    return if declared

    add(:price_claim_without_ledger, :inconclusive,
        "A currency-labelled amount appears in the copy but has no price claim record.",
        claim: token[:text], suggestion: "Add a price claim record or remove the amount.")
  end

  def amount_mismatch(token, product_price, amount)
    add(:price_amount_mismatch, :fail,
        "A currency-labelled amount in the copy differs from the feed price.",
        claim: token[:text], evidence: { product_price_cents: product_price, copy_amount_cents: amount })
  end

  def currency_mismatch(token, currency, copy_currency)
    add(:price_currency_mismatch, :fail,
        "A currency-labelled amount in the copy uses a different currency from the feed.",
        claim: token[:text], evidence: { product_currency: currency, copy_currency: })
  end

  def currency_unknown(token)
    add(:price_currency_unresolved, :inconclusive,
        "The currency marker is ambiguous for the product market.",
        claim: token[:text], suggestion: "Use an explicit currency code.")
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

  def marker_status(text, expected)
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
    normalized = normalize(text)
    negative = %w[out of stock unavailable sold out utsolgt ikke pa lager].any? { |phrase| normalized.include?(phrase) }
    positive = !negative && %w[in stock available now pa lager tilgjengelig na].any? { |phrase| normalized.include?(phrase) }
    return nil if positive == negative

    positive
  end

  def copy_contains?(phrase)
    value = normalize(phrase)
    !value.empty? && normalize(copy_text).include?(value)
  end

  def copy_text
    %i[headline body cta].filter_map do |key|
      value = read(@creative, key)
      value.to_s unless blank?(value)
    end.join(" ")
  end

  def normalize(value) = value.to_s.downcase.gsub(/[^\p{Alnum}]+/u, " ").strip

  def read(record, key)
    return if record.nil?
    return record[key] if record.is_a?(Hash) && record.key?(key)
    return record[key.to_s] if record.is_a?(Hash) && record.key?(key.to_s)
    return record.public_send(key) if record.respond_to?(key)

    nil
  end

  def blank?(value) = value.nil? || value.to_s.strip.empty?

  def add(code, status, message, claim: nil, evidence: nil, suggestion: nil, confidence: nil)
    @findings << Master::Review::CopyReview::Finding.new(
      code:, status:, message:, claim: claim&.to_s,
      evidence:, suggestion:, confidence:
    )
  end
end
