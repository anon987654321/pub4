# frozen_string_literal: true

require "digest"
require "json"
require "review/copy_review"

# The request boundary for the paid copy-review operation. It accepts only
# the declared creative/product fields, bounds the payload, and fingerprints
# both inputs and the exact reviewer source. Submitted product facts remain
# caller-supplied; a reference string or a digest is not independent proof.
class CopyReviewCheck
  MAX_INPUT_BYTES = 100_000
  CREATIVE_FIELDS = %w[headline body cta locale disclosure claims].freeze
  CREATIVE_TEXT_FIELDS = %w[headline body cta locale disclosure].freeze
  PRODUCT_TEXT_FIELDS = %w[source external_id title merchant program_id currency category market last_seen_at].freeze
  CLAIM_FIELDS = %w[kind text reference source_reference].freeze
  PRODUCT_FIELDS = %w[
    source external_id title merchant program_id price_cents currency
    category market in_stock placeholder last_seen_at
  ].freeze
  REVIEWER_FILES = %w[
    review/copy_review.rb
    review/copy_review/claim_review.rb
    review/copy_review/inventory_review.rb
  ].freeze

  Prepared = Data.define(
    :creative, :product, :market, :creative_sha256, :product_sha256, :reviewer_sha256
  )
  Result = Data.define(
    :report, :creative_sha256, :product_sha256, :reviewer_sha256
  )

  class InvalidInput < StandardError; end

  def self.prepare(creative:, product: nil, market: nil)
    creative = clean_hash(creative, "creative", CREATIVE_FIELDS)
    product = clean_hash(product, "product", PRODUCT_FIELDS) unless product.nil?

    validate_string_fields!(creative, CREATIVE_TEXT_FIELDS, "creative")
    if creative.key?("claims") && !creative["claims"].nil?
      claims = creative["claims"]
      raise InvalidInput, "creative.claims must be an array" unless claims.is_a?(Array)

      creative["claims"] = claims.each_with_index.map do |claim, index|
        normalized = clean_hash(claim, "creative.claims[#{index}]", CLAIM_FIELDS)
        validate_string_fields!(normalized, CLAIM_FIELDS, "creative.claims[#{index}]")
        normalized
      end
    end

    if product
      validate_string_fields!(product, PRODUCT_TEXT_FIELDS, "product")
      if product.key?("price_cents") && !product["price_cents"].nil? && !product["price_cents"].is_a?(Integer)
        raise InvalidInput, "product.price_cents must be an integer in minor currency units"
      end
      %w[in_stock placeholder].each do |field|
        value = product[field]
        next if value.nil? || value == true || value == false

        raise InvalidInput, "product.#{field} must be true, false or null"
      end
    end

    unless market.nil? || market.is_a?(String)
      raise InvalidInput, "market must be a string"
    end
    normalized_market = market.to_s.strip.upcase.presence
    payload = { "creative" => creative, "product" => product, "market" => normalized_market }
    bytes = JSON.generate(canonical(payload)).bytesize
    raise InvalidInput, "copy-review input exceeds #{MAX_INPUT_BYTES} bytes" if bytes > MAX_INPUT_BYTES

    Prepared.new(
      creative:,
      product:,
      market: normalized_market,
      creative_sha256: digest(creative),
      product_sha256: product && digest(product),
      reviewer_sha256: reviewer_digest
    )
  rescue JSON::GeneratorError, EncodingError, TypeError => e
    raise InvalidInput, "copy-review input is not valid JSON data (#{e.class})"
  end

  def self.validate_string_fields!(record, fields, name)
    fields.each do |field|
      value = record[field]
      next if value.nil? || value.is_a?(String)

      raise InvalidInput, "#{name}.#{field} must be a string or null"
    end
  end
  private_class_method :validate_string_fields!

  def self.call(prepared)
    report = Master::Review::CopyReview.review(
      creative: prepared.creative,
      product: prepared.product,
      market: prepared.market
    )
    Result.new(
      report:,
      creative_sha256: prepared.creative_sha256,
      product_sha256: prepared.product_sha256,
      reviewer_sha256: prepared.reviewer_sha256
    )
  end

  def self.clean_hash(value, name, allowed)
    value = value.to_unsafe_h if value.respond_to?(:to_unsafe_h)
    raise InvalidInput, "#{name} must be an object" unless value.is_a?(Hash)

    normalized = value.to_h { |key, item| [key.to_s, item] }
    unknown = normalized.keys - allowed
    raise InvalidInput, "#{name} contains unsupported fields: #{unknown.sort.join(', ')}" if unknown.any?

    normalized
  end
  private_class_method :clean_hash

  def self.canonical(value)
    case value
    when Hash
      value.keys.sort.each_with_object({}) { |key, out| out[key] = canonical(value[key]) }
    when Array
      value.map { |item| canonical(item) }
    else
      value
    end
  end
  private_class_method :canonical

  def self.digest(value)
    Digest::SHA256.hexdigest(JSON.generate(canonical(value)))
  end
  private_class_method :digest

  def self.reviewer_digest
    source = REVIEWER_FILES.map do |path|
      File.binread(File.join(Master::ROOT, "lib", path))
    end
    Digest::SHA256.hexdigest(source.join("\0"))
  end
  private_class_method :reviewer_digest
end
