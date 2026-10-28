# frozen_string_literal: true

require "minitest/autorun"
require "erb"
require "yaml"

# The RAILS side of the ad visual contract: every shared ad partial must be
# buildable only through the token contract MASTER/data/tokens.yml names, and
# every advertising surface must carry its disclosure. MASTER audits rendered
# ads with tools/visual/audit_ad.rb; this test binds the source partials to
# that same contract, so an ad that passes the audit cannot be assembled from
# a partial the contract would reject.
#
# The two surfaces carry their disclosure differently and both ways are
# contractual: _ad_slot (AdSense) is consent-gated and labelled through
# t("shared.advertisement"); _affiliate_feed_unit (Tradedoubler/Amazon)
# renders the affiliate_disclosure partial and a per-link paid-link mark.
class AdVisualContractTest < Minitest::Test
  SHARED = File.expand_path("../__shared/app/views/shared", __dir__)
  TOKENS = YAML.safe_load(
    File.read(File.expand_path("../../MASTER/data/tokens.yml", __dir__), encoding: "UTF-8"),
    aliases: true
  )
  CONTRACT = TOKENS.fetch("tokens").fetch("ad_visual_contract")

  def test_shared_ad_partials_exist
    %w[_ad_slot.html.erb _affiliate_feed_unit.html.erb _affiliate_disclosure.html.erb].each do |partial|
      assert File.file?(File.join(SHARED, partial)), "missing shared ad partial #{partial}"
    end
  end

  def test_affiliate_unit_names_the_contract_family_and_carries_the_disclosure
    text = read("_affiliate_feed_unit.html.erb")
    assert text.include?("affiliate_feed_unit"), "the unit must keep its contract class family"
    assert text.include?("shared/affiliate_disclosure"),
           "the affiliate unit must render the disclosure partial"
    assert text.include?("rel=\"noopener sponsored\""),
           "outbound affiliate links must be marked sponsored"
  end

  def test_affiliate_unit_marks_each_paid_link
    text = read("_affiliate_feed_unit.html.erb")
    assert text.include?("affiliate_feed_link_disclosure"),
           "each affiliate link carries its own paid-link disclosure"
  end

  def test_ad_slot_is_consent_gated_and_labelled
    text = read("_ad_slot.html.erb")
    assert text.include?("advertising_consent?"),
           "_ad_slot must render nothing without an advertising-consent signal"
    assert text.include?("ad-slot-label"),
           "_ad_slot must label the surface as an advertisement"
  end

  def test_ad_partials_carry_no_hard_coded_hex_colors
    %w[_ad_slot.html.erb _affiliate_feed_unit.html.erb _affiliate_disclosure.html.erb].each do |partial|
      hexes = read(partial).scan(/#[0-9a-fA-F]{3,8}\b/)
      assert_empty hexes, "#{partial} hard-codes colors #{hexes.uniq}; every color resolves through a token"
    end
  end

  def test_disclosure_partial_says_what_the_contract_requires
    assert read("_affiliate_disclosure.html.erb").match?(/affiliate|sponsor|advertis/i),
           "the disclosure must name the relationship: affiliate, sponsored or advertising"
  end

  def test_master_audit_tool_covers_the_manifest_contract
    tool = File.read(File.expand_path("../../MASTER/tools/visual/audit_ad.rb", __dir__), encoding: "UTF-8")
    %w[html css placement].each do |key|
      assert tool.include?(key), "tools/visual/audit_ad.rb must require #{key} evidence in every manifest"
    end
    assert tool.include?("BrowserlessMeasurements"),
           "the audit must measure from source when no render evidence is supplied"
  end

  def test_tradedoubler_service_and_conversion_model_survive_the_contract
    %w[app/services/shared/tradedoubler.rb app/models/shared/affiliate_product.rb].each do |path|
      full = File.expand_path("../__shared/#{path}", __dir__)
      assert File.file?(full), "the monetisation stack lost #{path}; the ad contract depends on it"
    end
  end

  private

  def read(partial)
    File.read(File.join(SHARED, partial), encoding: "UTF-8")
  end
end
