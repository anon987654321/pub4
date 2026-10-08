# frozen_string_literal: true

module Shared
  # One read-only growth report over the signals pub4 already records.
  #
  # It deliberately does not create a second analytics identity or pretend that
  # channels can be compared where the underlying systems use different units.
  # Page views are visits; outbound clicks are merchant traffic; marketplace
  # orders are Brgen sales; affiliate conversions are external network sales;
  # partner conversions are partner-attributed Brgen sales.
  class GrowthReport
    DEFAULT_WINDOW = 30.days

    def initialize(window: DEFAULT_WINDOW, now: Time.current)
      @window = window
      @now = now
    end

    def since = @now - @window

    def visits
      return 0 unless defined?(Shared::VisitCount)

      Shared::VisitCount.since(since.to_date).sum(:count)
    end

    def visits_by_host
      return {} unless defined?(Shared::VisitCount)

      Shared::VisitCount.by_host(since: since.to_date)
    end

    def outbound_clicks
      return 0 unless defined?(Shared::OutboundClick)

      Shared::OutboundClick.where(created_at: since..).count
    end

    def outbound_clicks_by_surface
      return {} unless defined?(Shared::OutboundClick)

      Shared::OutboundClick.where(created_at: since..).group(:surface).order(count_all: :desc).count
    end

    def paid_orders
      return 0 unless defined?(Marketplace::Order)

      Marketplace::Order.where(payment_status: "paid", paid_at: since..).count
    end

    def google_attributed_orders
      return 0 unless defined?(Marketplace::Order)

      Marketplace::Order.where(payment_status: "paid", paid_at: since..).where.not(gclid: [ nil, "" ]).count
    end

    def affiliate_conversions
      return 0 unless defined?(Shared::AffiliateConversion)

      Shared::AffiliateConversion.where(created_at: since..).count
    end

    def affiliate_order_value
      return 0 unless defined?(Shared::AffiliateConversion)

      Shared::AffiliateConversion.where(created_at: since..).sum(:order_value).to_f
    end

    def partner_conversions
      return 0 unless defined?(Partner::Conversion)

      Partner::Conversion.where(created_at: since..).count
    end

    def partner_order_value_cents
      return 0 unless defined?(Partner::Conversion)

      Partner::Conversion.where(created_at: since..).sum(:order_value_cents).to_i
    end

    def abandoned_cart_reminders
      return 0 unless defined?(Marketplace::Checkout) && Marketplace::Checkout.column_names.include?("abandoned_cart_reminded_at")

      Marketplace::Checkout.where(abandoned_cart_reminded_at: since..).count
    end

    # Never add revenue across unlike systems. The report exposes the units so
    # the operator can compare each channel with the source that owns its truth.
    def render
      lines = [ "growth report — #{@window.inspect} to #{@now.utc.iso8601}" ]
      lines << ""
      lines << "  traffic"
      lines << format("    visits                     %d", visits)
      visits_by_host.first(12).each { |host, count| lines << format("    %-28s %d", host, count) }
      lines << ""
      lines << "  commerce"
      lines << format("    paid marketplace orders    %d", paid_orders)
      lines << format("    Google-attributed orders   %d", google_attributed_orders)
      lines << format("    partner conversions        %d", partner_conversions)
      lines << format("    partner order value        %d øre", partner_order_value_cents)
      lines << format("    cart recovery emails       %d", abandoned_cart_reminders)
      lines << ""
      lines << "  affiliate"
      lines << format("    outbound merchant clicks   %d", outbound_clicks)
      outbound_clicks_by_surface.first(12).each { |surface, count| lines << format("    %-28s %d", surface || "(none)", count) }
      lines << format("    network conversions        %d", affiliate_conversions)
      lines << format("    external order value       %.2f", affiliate_order_value)
      lines.join("\n")
    end
  end
end
