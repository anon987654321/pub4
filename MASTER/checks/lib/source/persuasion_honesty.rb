# frozen_string_literal: true

require_relative "../../support/check_result"
require_relative "../../support/source_contract"

module Deploy
  # Persuasion honesty: the grey patterns must stay grey. Scarcity, countdowns
  # and price anchors may render only from measured truth — listing stock, a
  # real ends_at, the trailing 30-day price-observation minimum — and a view
  # must never hardcode a persuasive number. The takeaway confirm screen must
  # render the whole bill — subtotal, delivery fee and tip inside the total —
  # so no charge can surface after the price was believed (PERSUASION_truth_
  # bearing). Checked beside payment_honesty because the same fail-honestly
  # contract covers anything that talks a visitor into paying.
  class PersuasionHonestyCheck
    ROOT = File.expand_path("../../../..", __dir__)
    RAILS = File.join(ROOT, "RAILS")

    REQUIRED = {
      "brgen_marketplace/app/models/marketplace/listing_price_observation.rb" =>
        /marketplace_listing_price_observations|trailing_30_days/,
      "brgen/db/migrate/20261104100000_create_marketplace_listing_price_observations.rb" =>
        /create_table :marketplace_listing_price_observations/,
      "brgen/db/schema.rb" => /marketplace_listing_price_observations/,
      "brgen_marketplace/app/models/marketplace/listing.rb" =>
        /SCARCITY_THRESHOLD|scarcity_quantity|omnibus_reference_price_cents|record_price_observation/,
      "brgen_marketplace/app/views/marketplace/deals/_card.html.erb" =>
        /persuasion\.was_price|persuasion\.only_n_left/,
      "brgen_marketplace/app/views/marketplace/listings/_card.html.erb" =>
        /persuasion\.only_n_left/,
      "brgen_marketplace/config/locales/en.yml" => /only_n_left|was_price/,
      "brgen_marketplace/config/locales/nb.yml" => /only_n_left|was_price/,
      "brgen_marketplace/engines/takeaway/app/views/takeaway/orders/show.html.erb" =>
        /takeaway\.subtotal|takeaway\.delivery|takeaway\.total/,
      "brgen_marketplace/engines/takeaway/app/views/takeaway/orders/new.html.erb" =>
        /min_order_delivery/,
    }.freeze

    # A persuasive number a human typed into a template is the definition of a
    # dark pattern: it renders identically for every listing, so it cannot be
    # true for every listing. Anchors, counts and deadlines come from data.
    # The takeaway order views price nothing by hand either: every krone on
    # the bill — delivery fee included — comes from the order or the
    # restaurant row, so a late-chosen fee can never be quieter than the
    # price the guest believed.
    FORBIDDEN = {
      "brgen_marketplace/app/views/marketplace/deals/_card.html.erb" =>
        /Før \d|Was \d|\d+ kr igjen|only \d+ left/i,
      "brgen_marketplace/app/views/marketplace/listings/_card.html.erb" =>
        /Før \d|Was \d|\d+ kr igjen|only \d+ left/i,
      "brgen_marketplace/engines/takeaway/app/views/takeaway/orders/show.html.erb" =>
        /\d+\s*(kr|NOK)|NOK\s*\d+/i,
      "brgen_marketplace/engines/takeaway/app/views/takeaway/orders/new.html.erb" =>
        /\d+\s*(kr|NOK)|NOK\s*\d+/i,
    }.freeze

    # rails_root: is what makes this check testable. A contract table is only
    # enforcement if a tree that violates it fails, and the only way to show
    # that is to run the check over a tree built to violate it.
    def self.run(rails_root: RAILS)
      new(rails_root:).run
    end

    def initialize(rails_root: RAILS)
      @rails_root = rails_root
    end

    def run
      @result = CheckResult.new

      SourceContract.require_patterns(@result, root: @rails_root, required: REQUIRED, check: "persuasion_honesty")

      FORBIDDEN.each do |rel, pat|
        path = File.join(@rails_root, rel)
        next unless File.file?(path)

        body = File.read(path)
        @result.fail("persuasion_honesty: #{rel} must not hardcode a persuasive number") if body.match?(pat)
      end

      listing = read("brgen_marketplace/app/models/marketplace/listing.rb")
      # The anchor is Omnibus-true only when it is a minimum over a bounded
      # window of observed prices, and only a strictly-lower current price may
      # render it.
      unless listing.match?(/30\.days|trailing_30_days/)
        @result.fail("persuasion_honesty: the anchor window must be bounded at 30 days")
      end
      unless listing.include?("minimum(:price_cents)")
        @result.fail("persuasion_honesty: the anchor must be the observed minimum, not a max or a guess")
      end
      unless listing.include?("price_cents >= was")
        @result.fail("persuasion_honesty: anchor renders only when the current price is strictly below the observed minimum")
      end
      # Scarcity must refuse every case where the number would lie: one of a
      # kind and variant-managed listings have no honest listing-level count.
      unless listing.include?("one_of_a_kind?") && listing.include?("varied?")
        @result.fail("persuasion_honesty: scarcity_quantity must gate on one_of_a_kind? and varied?")
      end

      @result.checked!(REQUIRED.size + FORBIDDEN.size + 4)
      @result
    end

    private

    # A deleted file is already reported by the REQUIRED table, so reading it
    # back must not raise on top of that: an exception here reaches the runner
    # as :errored, which blocks nothing and hides a finding already made.
    def read(relative)
      path = File.join(@rails_root, relative)
      File.file?(path) ? File.read(path) : ""
    end
  end
end
