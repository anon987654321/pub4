# frozen_string_literal: true

require "net/http"
require "uri"
require_relative "../../../OPENBSD/lib/deploy_inventory"
require_relative "../../../OPENBSD/lib/gate_result"
require_relative "../../crawl_support"

module Deploy
  # Checkout without PSP keys must fail honestly (MASTER fail_fast / good_design_is_honest).
  class PaymentHonestyGate
    ROOT = File.expand_path("../../..", __dir__)
    RAILS = File.join(ROOT, "RAILS")

    REQUIRED = {
      "brgen/app/services/marketplace/payments/not_configured.rb" => /NotConfigured/,
      "brgen/app/services/marketplace/payments/stripe_checkout.rb" => /NotConfigured|configured\?/,
      "brgen/app/services/marketplace/payments/vipps_checkout.rb" => /NotConfigured|configured\?/,
      "brgen/app/controllers/marketplace/checkouts_controller.rb" => /NotConfigured|provider/,
      "brgen/app/views/marketplace/carts/show.html.erb" => /Pay with Vipps|Pay with Stripe|not configured/i,
      "brgen/config/routes.rb" => /checkout|webhooks/,
    }.freeze

    def self.run
      new.run
    end

    def run
      @result = GateResult.new
      REQUIRED.each do |rel, pat|
        path = File.join(RAILS, rel)
        unless File.file?(path)
          @result.fail("payment_honesty: missing #{rel}")
          next
        end
        body = File.read(path)
        @result.fail("payment_honesty: #{rel} missing #{pat.inspect}") unless body.match?(pat)
      end

      # Stripe/Vipps must raise NotConfigured when keys blank — source contract
      stripe = File.read(File.join(RAILS, "brgen/app/services/marketplace/payments/stripe_checkout.rb"))
      @result.fail("payment_honesty: StripeCheckout must raise NotConfigured") unless stripe.match?(/raise NotConfigured/)
      vipps = File.read(File.join(RAILS, "brgen/app/services/marketplace/payments/vipps_checkout.rb"))
      @result.fail("payment_honesty: VippsCheckout must raise NotConfigured") unless vipps.match?(/raise NotConfigured/)

      live_cart_probe
      @result
    end

    private

    def live_cart_probe
      inv = Inventory.new(root: ROOT).apps.find { |a| a.name == "brgen" }
      return @result.inconclusive!("payment_honesty: brgen not in inventory — live cart not probed") unless inv
      return @result.inconclusive!("payment_honesty: brgen port closed — live cart not probed") unless CrawlSupport.port_open?("127.0.0.1", inv.port)

      # Guest cart should redirect to sign-in or show cart — never 500
      res = fetch("http://127.0.0.1:#{inv.port}/cart", host: "markedsplass.brgen.no")
      code = res.code.to_i
      @result.fail("payment_honesty: cart HTTP #{code}") unless code.between?(200, 399)
      body = res.body.to_s
      @result.fail("payment_honesty: cart shows Exception") if body.include?("Exception") || body.include?("Routing Error")
    rescue StandardError => e
      @result.fail("payment_honesty live: #{e.class}: #{e.message}")
    end

    def fetch(url, host: nil)
      uri = URI(url)
      Net::HTTP.start(uri.host, uri.port, open_timeout: 8, read_timeout: 12) do |http|
        req = Net::HTTP::Get.new(uri.request_uri)
        req["Host"] = host if host
        http.request(req)
      end
    end
  end
end
