# frozen_string_literal: true

require_relative "../../../../OPENBSD/lib/gate_result"

module Deploy
  # Partner-marketing honesty: placeholders must be flagged, disclosures present,
  # TradeDoubler client must not invent tracking without a token, and import is
  # table-first (no live HTTP required to render deals).
  class AffiliateHonestyGate
    ROOT = File.expand_path("../../../..", __dir__)
    RAILS = File.join(ROOT, "RAILS")

    REQUIRED = {
      "shared/app/models/shared/affiliate_product.rb" => /placeholder|scope :real|STALE_AFTER/,
      "shared/app/services/shared/tradedoubler.rb" => /configured\?|matrix_uri|products_token|placeholder/,
      "shared/app/services/shared/affiliate.rb" => /NETWORK_NAMES|stored_deals|import_all!/,
      "brgen/lib/brgen/affiliate_placeholders.rb" => /placeholder: true/,
      "brgen/app/views/shared/_affiliate_deals.html.erb" => /placeholder|sponsored|affiliate_disclosure/,
      "shared/app/views/shared/_affiliate_disclosure.html.erb" => /affiliate_disclosure_text/,
      "shared/app/models/shared/affiliate_conversion.rb" => /message_type_id|record_from_postback!/,
      "brgen/app/controllers/webhooks/tradedoubler_controller.rb" => /unauthorized|TRADEDOUBLER_WEBHOOK_SECRET|secure_compare/,
      "brgen/app/jobs/affiliate_import_job.rb" => /AffiliateImportJob|import_all!/,
      "brgen/app/jobs/link_converter_sync_job.rb" => /LinkConverterSyncJob|td-lc/,
      "brgen/config/recurring.yml" => /affiliate_import|link_converter_sync/,
      "brgen/app/services/partner_marketing.rb" => /SELF_REFERRAL|attribute_order!/,
      "amber/app/services/shop_the_look.rb" => /ShopTheLook|Suggestion/,
    }.freeze

    FORBIDDEN = {
      "brgen/lib/brgen/affiliate_placeholders.rb" => %r{clk\.tradedoubler|pdt\.tradedoubler},
    }.freeze

    def self.run
      new.run
    end

    def run
      @result = GateResult.new

      REQUIRED.each do |rel, pat|
        path = File.join(RAILS, rel)
        unless File.file?(path)
          @result.fail("affiliate_honesty: missing #{rel}")
          next
        end
        body = File.read(path)
        @result.fail("affiliate_honesty: #{rel} missing #{pat.inspect}") unless body.match?(pat)
      end

      FORBIDDEN.each do |rel, pat|
        path = File.join(RAILS, rel)
        next unless File.file?(path)

        body = File.read(path)
        @result.fail("affiliate_honesty: #{rel} must not invent TD tracking URLs") if body.match?(pat)
      end

      client = File.read(File.join(RAILS, "shared/app/services/shared/tradedoubler.rb"))
      unless client.match?(/def configured\?.*products_token|def configured\? = products_token/)
        @result.fail("affiliate_honesty: Tradedoubler.configured? must gate on token")
      end
      unless client.include?("matrix_uri") && client.include?("fid")
        @result.fail("affiliate_honesty: Products API must use matrix URI + fid")
      end

      webhook = File.read(File.join(RAILS, "brgen/app/controllers/webhooks/tradedoubler_controller.rb"))
      unless webhook.match?(/return false if secret\.blank?|return head\(:unauthorized\)/)
        @result.fail("affiliate_honesty: conversions webhook must fail closed")
      end

      @result.checked!(REQUIRED.size + FORBIDDEN.size + 3)
      @result
    end
  end
end
