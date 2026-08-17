# frozen_string_literal: true

require "net/http"
require "uri"
require_relative "../../../../OPENBSD/lib/deploy_inventory"
require_relative "../../../../OPENBSD/lib/gate_result"
require_relative "../../../tools/crawl_support"

module Deploy
  # Checkout without PSP keys must fail honestly (MASTER fail_fast / good_design_is_honest).
  class PaymentHonestyGate
    ROOT = File.expand_path("../../../..", __dir__)
    RAILS = File.join(ROOT, "RAILS")

    # The vertical-as-engine split moved marketplace's controllers, views and
    # routes to engines/marketplace/ and left the payment *services* in the host.
    # This gate kept the pre-split paths, so it failed on "missing" files that had
    # only moved — and would have gone on failing identically had the checkout
    # actually been deleted. Engine paths below; host paths for what stayed.
    ENGINE = "brgen/engines/marketplace"

    REQUIRED = {
      "brgen/app/services/marketplace/payments/not_configured.rb" => /NotConfigured/,
      "brgen/app/services/marketplace/payments/stripe_checkout.rb" => /NotConfigured|configured\?/,
      "brgen/app/services/marketplace/payments/vipps_checkout.rb" => /NotConfigured|configured\?/,
      "#{ENGINE}/app/controllers/marketplace/checkouts_controller.rb" => /NotConfigured|provider/,
      # i18n keys or EN fallbacks after cart polish
      "#{ENGINE}/app/views/marketplace/carts/show.html.erb" => /pay_vipps|pay_stripe|Pay with Vipps|Pay with Stripe|not configured|cart_honest_pay|marketplace\.pay_/i,
      # Checkout + PSP webhook routes are drawn on the engine now. The host
      # routes.rb still matches /webhooks/ via webhooks/tradedoubler, so keeping
      # the assertion there would have passed on an unrelated route forever.
      # Both must be present, hence the lookahead rather than an alternation.
      "#{ENGINE}/config/routes.rb" => /(?=.*checkout)(?=.*webhooks)/m,
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
      # The source contract above is the bulk of this gate and does not need a
      # booted app; only the cart probe does. Counting it stops a closed brgen port
      # from reporting the whole gate as having measured nothing.
      @result.checked!(REQUIRED.size + 2)

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
