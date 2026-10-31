# frozen_string_literal: true

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

  DISCLOSURE_TERMS = {
    "en" => /\b(?:advertisement|sponsored|affiliate(?:\s+link)?|paid partnership)\b/i,
    "nb" => /\b(?:annonse|reklame|annonselenke|reklamelenke|affiliate(?:lenke|link)?)\b/i,
  }.freeze

  def self.review(**arguments) = new(**arguments).review

  def initialize(creative:, product:, market: nil, now: Time.now.utc,
                 max_age_seconds: DEFAULT_MAX_AGE_SECONDS)
    @creative = creative
    @product = product
    @market = blank?(market) ? nil : market.to_s.upcase
    @now = InventoryReview.coerce_time(now) || raise(ArgumentError, "now must be a Time or parseable timestamp")
    @max_age_seconds = Integer(max_age_seconds)
    raise ArgumentError, "max_age_seconds must be non-negative" if @max_age_seconds.negative?
  end

  def review
    findings = assess_copy_structure
    inventory = inventory_report
    findings.concat(inventory.findings)
    findings.concat(assess_disclosure(inventory.product))
    findings.concat(ClaimReview.new(creative: @creative, product: @product).review.findings)
    build_report(findings, inventory)
  end

  private

  def inventory_report
    InventoryReview.new(product: @product, market: @market, now: @now,
                        max_age_seconds: @max_age_seconds).review
  end

  def build_report(findings, inventory)
    counts = findings.group_by(&:status).transform_values(&:size)
    Report.new(
      status: report_status(counts),
      findings: findings.freeze,
      evidence: report_evidence(inventory).freeze,
      summary: report_summary(counts),
      version: VERSION,
    )
  end

  def report_status(counts)
    return :fail if counts.fetch(:fail, 0).positive?
    return :inconclusive if counts.fetch(:inconclusive, 0).positive?

    :pass
  end

  def report_summary(counts)
    {
      pass: counts.fetch(:pass, 0),
      fail: counts.fetch(:fail, 0),
      inconclusive: counts.fetch(:inconclusive, 0),
    }.freeze
  end

  def report_evidence(inventory)
    {
      read_only: true,
      product: inventory.product,
      product_snapshot_sha256: inventory.sha256,
      locale: read(@creative, :locale)&.to_s,
      claim_count: Array(read(@creative, :claims)).size,
      scope: "declared_copy_and_supported_feed_fields",
      limitations: report_limitations,
    }
  end

  def report_limitations
    [
      "Natural-language meaning and claim-ledger completeness are not independently proven.",
      "External references are not fetched; unsupported claim kinds remain INCONCLUSIVE.",
      "Disclosure wording is checked here; rendered prominence and consent use separate controls."
    ]
  end

  def assess_copy_structure
    [headline_finding, cta_finding, locale_finding]
  end

  def headline_finding
    return finding(:headline_missing, :fail, "A creative headline is required.",
                   suggestion: "Add a specific headline.") if blank?(read(@creative, :headline))

    finding(:headline_present, :pass, "A headline is present.", confidence: 1.0)
  end

  def cta_finding
    return finding(:cta_missing, :fail, "A call to action is missing.",
                   suggestion: "Add a clear action that matches the destination.") if blank?(read(@creative, :cta))

    finding(:cta_present, :pass, "A call to action is present.", confidence: 1.0)
  end

  def locale_finding
    locale = read(@creative, :locale)
    return finding(:locale_unresolved, :inconclusive,
                   "The locale is missing or is outside the reviewed English/Bokmål set.",
                   evidence: { locale: }) unless locale_family(locale)

    finding(:locale_declared, :pass, "A supported copy locale is declared.",
            evidence: { locale: locale.to_s }, confidence: 1.0)
  end

  def assess_disclosure(product_state)
    return [] unless product_state && SOURCES.include?(product_state[:source])

    disclosure = read(@creative, :disclosure)
    return [missing_disclosure] if blank?(disclosure)
    return [unrecognised_disclosure] unless disclosure_label?(disclosure)

    [finding(:affiliate_disclosure_present, :pass,
             "An explicit affiliate/sponsored disclosure is present in the supplied copy.",
             evidence: { disclosure: disclosure.to_s }, confidence: 1.0)]
  end

  def missing_disclosure
    finding(:affiliate_disclosure_missing, :fail,
            "Affiliate copy is missing its explicit commercial disclosure.",
            suggestion: "Add a translated affiliate/sponsored disclosure. Visual prominence is assessed separately.")
  end

  def unrecognised_disclosure
    finding(:affiliate_disclosure_unrecognised, :fail,
            "The disclosure has no recognised commercial label for the declared locale.",
            evidence: { locale: read(@creative, :locale).to_s })
  end

  def disclosure_label?(disclosure)
    family = locale_family(read(@creative, :locale))
    terms = family ? DISCLOSURE_TERMS[family] : Regexp.union(DISCLOSURE_TERMS.values)
    terms.match?(disclosure.to_s)
  end

  def finding(code, status, message, **details)
    Finding.new(code:, status:, message:, claim: details[:claim],
                evidence: details[:evidence], suggestion: details[:suggestion],
                confidence: details[:confidence])
  end

  def read(record, key)
    return if record.nil?
    return record[key] if record.is_a?(Hash) && record.key?(key)
    return record[key.to_s] if record.is_a?(Hash) && record.key?(key.to_s)
    return record.public_send(key) if record.respond_to?(key)

    nil
  end

  def blank?(value) = value.nil? || value.to_s.strip.empty?

  def locale_family(value)
    family = value.to_s.downcase.split(/[-_]/).first
    DISCLOSURE_TERMS.key?(family) ? family : nil
  end
end
