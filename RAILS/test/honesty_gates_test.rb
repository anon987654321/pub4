# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "support/method_swap"
require_relative "../gates/lib/source/payment_honesty"
require_relative "../gates/lib/source/affiliate_honesty"

# Both honesty gates are tables of file -> pattern, and a table is only
# enforcement if a tree that breaks it fails. Running either against the real
# RAILS/ tree and asserting "passed" proves nothing: it passes identically
# against a gate whose body is `GateResult.new`.
#
# So each defect below is planted into a tree built for the purpose, the gate is
# pointed at that tree, and the assertion is that the gate names the defect.
# Then the same tree without the defect must come back clean.
#
# The live half of payment_honesty is held off with a closed port, which is its
# own documented state: the source contract is the bulk of the gate and counts
# as measured, so a closed brgen port leaves the gate passing rather than
# reporting that it checked nothing.
class HonestyGatesTest < Minitest::Test
  include MethodSwap

  ENGINE = "brgen/engines/marketplace"

  # The smallest tree that satisfies PaymentHonestyGate::REQUIRED and both
  # raise-site read-backs. Content is chosen to match the declared pattern and
  # nothing else — a fixture that copied the real files would pass or fail with
  # the tree rather than with the gate.
  PAYMENT_TREE = {
    "brgen/app/services/marketplace/payments/not_configured.rb" =>
      "class NotConfigured < StandardError; end\n",
    "brgen/app/services/marketplace/payments/stripe_checkout.rb" =>
      "def call\n  raise NotConfigured unless configured?\nend\n",
    "brgen/app/services/marketplace/payments/stripe_refund.rb" =>
      "StripeCheckout.ensure!\n",
    "brgen/app/services/marketplace/payments/stripe_transfer.rb" =>
      "StripeCheckout.ensure!\n",
    "brgen/app/services/marketplace/payments/vipps_checkout.rb" =>
      "def call\n  raise NotConfigured unless configured?\nend\n",
    "#{ENGINE}/app/controllers/marketplace/checkouts_controller.rb" =>
      "def provider = params[:provider]\n",
    "#{ENGINE}/app/views/marketplace/carts/show.html.erb" =>
      "<%= t(\"marketplace.pay_vipps\") %>\n",
    "#{ENGINE}/config/routes.rb" =>
      "post \"checkout\"\npost \"webhooks/tradedoubler\"\n",
  }.freeze

  # The smallest tree that satisfies AffiliateHonestyGate::REQUIRED, its
  # FORBIDDEN table and its three hand-written client assertions.
  AFFILIATE_TREE = {
    "shared/app/models/shared/affiliate_product.rb" => "scope :real, -> { where(placeholder: false) }\n",
    "shared/app/services/shared/tradedoubler.rb" =>
      "def configured? = products_token.present?\nMATRIX = \"matrix_uri\"\nFID = \"fid\"\n",
    "shared/app/services/shared/affiliate.rb" => "def import_all!; end\n",
    "brgen/lib/brgen/affiliate_placeholders.rb" => "{ placeholder: true }\n",
    "brgen/app/views/shared/_affiliate_deals.html.erb" => "<%= render \"shared/affiliate_disclosure\" %>\n",
    "shared/app/views/shared/_affiliate_disclosure.html.erb" => "<%= t(\"affiliate_disclosure_text\") %>\n",
    "shared/app/models/shared/affiliate_conversion.rb" => "def self.record_from_postback!(params); end\n",
    "brgen/app/controllers/webhooks/tradedoubler_controller.rb" =>
      "def create\n  return head(:unauthorized) unless secure_compare(token, secret)\nend\n",
    "brgen/app/jobs/affiliate_import_job.rb" => "class AffiliateImportJob; end\n",
    "brgen/app/jobs/link_converter_sync_job.rb" => "class LinkConverterSyncJob; end\n",
    "brgen/config/recurring.yml" => "affiliate_import:\n  schedule: every day\n",
    "brgen/app/services/partner_marketing.rb" => "SELF_REFERRAL = true\n",
    "amber/app/services/shop_the_look.rb" => "class ShopTheLook; end\n",
  }.freeze

  # files: the whole tree, already carrying whatever defect this test plants.
  # The port stub keeps payment_honesty's live cart probe off a machine that may
  # or may not have brgen listening, so the verdict is the source contract's.
  def gate(klass, files)
    Dir.mktmpdir("gate-honesty") do |dir|
      files.each do |rel, body|
        path = File.join(dir, rel)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, body)
      end
      swap_value(CrawlSupport, :port_open?, false) do
        return klass.run(rails_root: dir)
      end
    end
  end

  def assert_names(result, pattern)
    assert result.failures.any? { |f| f.match?(pattern) },
           "no failure matched #{pattern.inspect}; got:\n  #{result.failures.join("\n  ")}"
  end

  def test_payment_honesty_passes_over_a_tree_that_keeps_the_contract
    result = gate(Deploy::PaymentHonestyGate, PAYMENT_TREE)

    assert_empty result.failures
    assert_equal :passed, result.outcome,
                 "the source contract is measured even with brgen's port closed"
  end

  # The gate exists for exactly this: a PSP client that stops refusing when it
  # has no keys takes money it cannot charge.
  def test_payment_honesty_fails_when_stripe_stops_raising_not_configured
    defect = PAYMENT_TREE.merge(
      "brgen/app/services/marketplace/payments/stripe_checkout.rb" =>
        "def call\n  Stripe::Session.create(configured?)\nend\n"
    )
    result = gate(Deploy::PaymentHonestyGate, defect)

    assert_names result, /StripeCheckout must raise NotConfigured/
    refute_predicate result, :ok?
  end

  def test_payment_honesty_fails_when_vipps_stops_raising_not_configured
    defect = PAYMENT_TREE.merge(
      "brgen/app/services/marketplace/payments/vipps_checkout.rb" => "def call = configured?\n"
    )

    assert_names gate(Deploy::PaymentHonestyGate, defect), /VippsCheckout must raise NotConfigured/
  end

  # A file that moved rather than died is the failure this gate already had
  # once, when the vertical became an engine. A file that is genuinely gone must
  # still fail, and it must say which one.
  def test_payment_honesty_fails_when_the_cart_view_is_deleted
    defect = PAYMENT_TREE.reject { |rel, _| rel.end_with?("carts/show.html.erb") }
    result = gate(Deploy::PaymentHonestyGate, defect)

    assert_names result, %r{missing .*carts/show\.html\.erb}
  end

  # The lookahead pattern wants checkout AND webhooks; an alternation would have
  # passed on either, which is how the host routes.rb satisfied this for free.
  def test_payment_honesty_fails_when_the_engine_routes_lose_the_psp_webhook
    defect = PAYMENT_TREE.merge("#{ENGINE}/config/routes.rb" => "post \"checkout\"\n")

    assert_names gate(Deploy::PaymentHonestyGate, defect), %r{#{ENGINE}/config/routes\.rb missing}
  end

  def test_affiliate_honesty_passes_over_a_tree_that_keeps_the_contract
    result = gate(Deploy::AffiliateHonestyGate, AFFILIATE_TREE)

    assert_empty result.failures
    assert_equal :passed, result.outcome
  end

  # configured? that answers true without a token is how a client starts
  # inventing tracking it was never issued.
  def test_affiliate_honesty_fails_when_configured_stops_gating_on_the_token
    defect = AFFILIATE_TREE.merge(
      "shared/app/services/shared/tradedoubler.rb" =>
        "def configured? = true\nMATRIX = \"matrix_uri\"\nFID = \"fid\"\n"
    )

    assert_names gate(Deploy::AffiliateHonestyGate, defect), /configured\? must gate on token/
  end

  def test_affiliate_honesty_fails_when_the_products_api_drops_the_matrix_uri
    defect = AFFILIATE_TREE.merge(
      "shared/app/services/shared/tradedoubler.rb" => "def configured? = products_token.present?\nFID = \"fid\"\n"
    )

    assert_names gate(Deploy::AffiliateHonestyGate, defect), /Products API must use matrix URI/
  end

  # The FORBIDDEN half. A placeholder deal is honest only while it carries no
  # tracking URL; inventing one attributes a click nobody earned.
  def test_affiliate_honesty_fails_when_a_placeholder_carries_a_tracking_url
    defect = AFFILIATE_TREE.merge(
      "brgen/lib/brgen/affiliate_placeholders.rb" =>
        "{ placeholder: true, url: \"https://clk.tradedoubler.com/click?a=1\" }\n"
    )

    assert_names gate(Deploy::AffiliateHonestyGate, defect), /must not invent TD tracking URLs/
  end

  def test_affiliate_honesty_fails_when_the_conversions_webhook_stops_failing_closed
    defect = AFFILIATE_TREE.merge(
      "brgen/app/controllers/webhooks/tradedoubler_controller.rb" =>
        "def create\n  Shared::AffiliateConversion.record_from_postback!(params)\nend\n"
    )

    assert_names gate(Deploy::AffiliateHonestyGate, defect), /webhook must fail closed/
  end

  def test_affiliate_honesty_fails_when_the_disclosure_partial_is_deleted
    defect = AFFILIATE_TREE.reject { |rel, _| rel.end_with?("_affiliate_disclosure.html.erb") }

    assert_names gate(Deploy::AffiliateHonestyGate, defect), %r{missing .*_affiliate_disclosure\.html\.erb}
  end

  # A deleted service must reach the runner as a finding, not as a crash. An
  # exception is recorded as :errored, which blocks nothing and buries the
  # missing-file failure the gate had already made.
  def test_a_deleted_service_is_a_finding_rather_than_a_gate_crash
    defect = PAYMENT_TREE.reject { |rel, _| rel.end_with?("stripe_checkout.rb") }
    result = gate(Deploy::PaymentHonestyGate, defect)

    assert_empty result.errors
    assert_names result, %r{missing .*stripe_checkout\.rb}
  end
end
