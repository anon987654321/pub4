# frozen_string_literal: true

# Clicks we sent, conversions that came back, and the gap between them.
#
# Before outbound clicks were counted there was no way to read a network
# dashboard: "nobody clicked" and "tracking is broken" both report zero
# conversions, and nothing in the tree knew which. This is the line that tells
# them apart, and it is the reason the click table exists.
#
# The join is `epi`, not the merchant name. Shared::OutboundClick records the
# merchant we linked to; AffiliateConversion records a program_id and the epi
# TradeDoubler echoed back. Only the epi appears on both sides, which is what epi
# is for.
#
# Three numbers matter more than the totals:
#
#   unattributed_conversions — a conversion whose epi matches no click we recorded.
#     Traffic is converting through a path we are not measuring (an old link, a
#     cached page, or the Link Converter rewriting an anchor the beacon missed).
#   silent_merchants — clicks with no conversion at all over the window. Normal for
#     small numbers; suspicious for a merchant with real traffic.
#   clicks_without_epi — links that went out with no epi, so any conversion they
#     produce lands in unattributed_conversions. This is the number to drive to zero.
class PartnerAttributionReport
  DEFAULT_WINDOW = 7.days

  def initialize(window: DEFAULT_WINDOW, now: Time.current)
    @window = window
    @now = now
  end

  def since = @now - @window

  def clicks_by_merchant
    Shared::OutboundClick.where(created_at: since..).group(:merchant).order(count_all: :desc).count
  end

  def click_epis
    @click_epis ||= Shared::OutboundClick.where(created_at: since..).where.not(epi: nil).distinct.pluck(:epi)
  end

  def clicks_total = Shared::OutboundClick.where(created_at: since..).count

  def clicks_without_epi = Shared::OutboundClick.where(created_at: since.., epi: nil).count

  def conversions
    return AffiliateConversion.none unless defined?(AffiliateConversion)

    AffiliateConversion.where(created_at: since..)
  end

  def conversions_by_state
    conversions.group(:message_type_id).count.transform_keys do |id|
      AffiliateConversion::MESSAGE_TYPES.fetch(id, "unknown(#{id})")
    end
  end

  def unattributed_conversions
    conversions.reject { |row| row.epi.present? && click_epis.include?(row.epi) }.size
  end

  def silent_merchants
    converted = conversions.filter_map(&:epi)
    clicks_by_merchant.reject { |_merchant, _count| converted.any? }.keys
  end

  # Plain text, because it goes to a log the operator greps and to a terminal.
  def render
    lines = [ "partner attribution — #{@window.inspect} to #{@now.utc.iso8601}" ]
    lines << format("  clicks              %d (%d with no epi)", clicks_total, clicks_without_epi)
    lines << format("  conversions         %d", conversions.count)
    lines << format("  unattributed        %d  (conversion with an epi we never recorded)",
                    unattributed_conversions)
    lines << ""
    lines << "  clicks by merchant:"
    if clicks_by_merchant.empty?
      lines << "    none — either nobody clicked, or the beacon is not firing. Check that a link " \
               "carries data-controller=\"outbound-click\"."
    else
      clicks_by_merchant.first(15).each { |merchant, count| lines << format("    %-28s %d", merchant || "(none)", count) }
    end
    lines << ""
    lines << "  conversions by state:"
    if conversions_by_state.empty?
      lines << "    none. With clicks above zero this is the useful zero: traffic went out and " \
               "nothing came back, so look at attribution before looking at the offer."
    else
      conversions_by_state.each { |state, count| lines << format("    %-28s %d", state, count) }
    end
    lines.join("\n")
  end
end
