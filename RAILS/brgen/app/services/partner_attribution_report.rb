# frozen_string_literal: true

require "set"

# Clicks we sent, conversions that came back, and the gap between them.
#
# The join is EPI, not the merchant name. Shared::OutboundClick records the
# merchant we linked to; Shared::AffiliateConversion records the EPI
# TradeDoubler echoed back. EPI carries coarse city and surface dimensions,
# never a visitor identity or an individual page path.
class PartnerAttributionReport
  DEFAULT_WINDOW = 7.days
  DIMENSIONS = %w[city surface].freeze

  def initialize(window: DEFAULT_WINDOW, now: Time.current)
    @window = window
    @now = now
  end

  def since = @now - @window

  def clicks = Shared::OutboundClick.where(created_at: since..)

  def clicks_by_merchant
    clicks.group(:merchant).order(count_all: :desc).count
  end

  def click_epis
    @click_epis ||= clicks.where.not(epi: nil).distinct.pluck(:epi).to_set
  end

  def clicks_total = clicks.count

  def clicks_without_epi = clicks.where(epi: nil).count

  def conversions
    return Shared::AffiliateConversion.none unless defined?(Shared::AffiliateConversion)

    Shared::AffiliateConversion.where(created_at: since..)
  end

  def approved_conversions = conversions.approved

  def conversions_by_state
    conversions.group(:message_type_id).count.transform_keys do |id|
      Shared::AffiliateConversion::MESSAGE_TYPES.fetch(id, "unknown(#{id})")
    end
  end

  def unattributed_conversions
    conversions.reject { |row| row.epi.present? && click_epis.include?(row.epi) }.size
  end

  def silent_merchants
    converted_epis = approved_conversions.filter_map(&:epi).to_set
    converted_merchants = clicks.where(epi: converted_epis.to_a).distinct.pluck(:merchant).to_set
    clicks_by_merchant.keys.reject { |merchant| converted_merchants.include?(merchant) }
  end

  # The network returns its commission in the conversion currency. Keep
  # currencies separate; converting with a guessed or stale FX rate would turn
  # an attribution report into a misleading revenue figure.
  def approved_commission_by_currency
    approved_conversions.group(:currency).sum(:publisher_commission).transform_values { |amount| amount || BigDecimal("0") }
  end

  # Coarse attribution only. The current EPI contract carries city and surface;
  # it does not carry a page slug, a visitor ID or a route. Missing dimensions
  # remain visible as unattributed rather than being inferred from a URL.
  def approved_commission_by_dimension(dimension)
    key = dimension.to_s
    raise ArgumentError, "dimension must be one of #{DIMENSIONS.join(', ')}" unless DIMENSIONS.include?(key)

    matched_epis = click_epis
    approved_conversions.each_with_object(Hash.new { |hash, bucket| hash[bucket] = BigDecimal("0") }) do |row, sums|
      matched = row.epi.present? && matched_epis.include?(row.epi)
      name = matched ? row.epi_parts[key].presence : nil
      currency = row.currency.presence || "unknown"
      sums[[name || "unattributed", currency]] += BigDecimal(row.publisher_commission.to_s.presence || "0")
    end.sort_by { |(name, currency), amount| [name, currency, amount] }.to_h
  end

  def clicks_by_dimension(dimension)
    key = dimension.to_s
    raise ArgumentError, "dimension must be one of #{DIMENSIONS.join(', ')}" unless DIMENSIONS.include?(key)

    clicks.where.not(epi: nil).each_with_object(Hash.new(0)) do |row, counts|
      name = row.epi.to_s.split("|").filter_map do |part|
        field, value = part.split(":", 2)
        value if field == key && value.present?
      end.first
      counts[name || "unattributed"] += 1
    end.sort_by { |name, count| [name, count] }.to_h
  end

  # Plain text, because it goes to a log the operator greps and to a terminal.
  def render
    lines = [ "partner attribution — #{@window.inspect} to #{@now.utc.iso8601}" ]
    lines << format("  clicks              %d (%d with no epi)", clicks_total, clicks_without_epi)
    lines << format("  conversions         %d", conversions.count)
    lines << format("  approved            %d", approved_conversions.count)
    lines << format("  unattributed        %d  (conversion with an epi we never recorded)",
                    unattributed_conversions)
    lines << ""
    lines << "  clicks by merchant:"
    if clicks_by_merchant.empty?
      lines << "    none — either nobody clicked, or the beacon is not firing. Check that a link " \
               "carries data-controller=\"outbound-click\"."
    else
      clicks_by_merchant.first(15).each do |merchant, count|
        lines << format("    %-28s %d", merchant || "(none)", count)
      end
    end
    lines << ""
    lines << "  approved publisher commission by currency:"
    if approved_commission_by_currency.empty?
      lines << "    none"
    else
      approved_commission_by_currency.each do |currency, amount|
        lines << format("    %-12s %12.2f", currency.presence || "unknown", amount.to_f)
      end
    end
    DIMENSIONS.each do |dimension|
      lines << ""
      lines << "  clicks by #{dimension}:"
      dimension_clicks = clicks_by_dimension(dimension)
      if dimension_clicks.empty?
        lines << "    none"
      else
        dimension_clicks.each { |name, count| lines << format("    %-28s %d", name, count) }
      end
      lines << "  approved commission by #{dimension}:"
      dimension_revenue = approved_commission_by_dimension(dimension)
      if dimension_revenue.empty?
        lines << "    none"
      else
        dimension_revenue.each do |(name, currency), amount|
          lines << format("    %-20s %12.2f %s", name, amount.to_f, currency)
        end
      end
    end
    lines << ""
    lines << "  conversions by state:"
    if conversions_by_state.empty?
      lines << "    none. With clicks above zero this is the useful zero: traffic went out and " \
               "nothing came back, so look at attribution before looking at the offer."
    else
      conversions_by_state.each do |state, count|
        lines << format("    %-28s %d", state, count)
      end
    end
    lines.join("\n")
  end
end
