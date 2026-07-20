# frozen_string_literal: true

require "test_helper"
require "brgen/domain_registry"
require "brgen/locale_bridge"
require "brgen/city_content"

class DomainRegistryTest < ActiveSupport::TestCase
  test "resolves brgen.no to bergen with norwegian locale" do
    result = Brgen::DomainRegistry.resolve("brgen.no")

    assert_equal "Bergen", result.entry.city
    assert_equal :nb, result.entry.locale
    assert_nil result.subapp
  end

  test "resolves amstrdam.nl marketplace subdomain" do
    result = Brgen::DomainRegistry.resolve("marktplaats.amstrdam.nl")

    assert_equal "amstrdam.nl", result.entry.domain
    assert_equal :marketplace, result.subapp
  end

  test "resolves kbenhvn.dk markedsplads marketplace subdomain" do
    result = Brgen::DomainRegistry.resolve("markedsplads.kbenhvn.dk")

    assert_equal "kbenhvn.dk", result.entry.domain
    assert_equal :marketplace, result.subapp
    assert_equal "markedsplads", result.entry.marketplace_subdomain
  end

  test "resolves lsangeles.com to los angeles" do
    result = Brgen::DomainRegistry.resolve("www.lsangeles.com")

    assert_equal "Los Angeles", result.entry.city
    assert_equal :"en-US", result.entry.locale
  end

  test "subdomain constants match routes constraints" do
    assert_equal %w[tv], Brgen::DomainRegistry::TV_SUBDOMAINS
    assert_equal %w[dating], Brgen::DomainRegistry::DATING_SUBDOMAINS
    assert_includes Brgen::DomainRegistry::PLAYLIST_SUBDOMAINS, "playlist"
    assert_includes Brgen::DomainRegistry::MARKETPLACE_SUBDOMAINS, "markedsplass"
  end

  test "subreddits for bergen include r/bergen" do
    subs = Brgen::DomainRegistry.subreddits_for("brgen.no")

    assert_includes subs, "bergen"
  end

  test "locale bridge maps dutch registry locale to nl" do
    assert_equal :nl, Brgen::LocaleBridge.resolve(:nl)
  end

  test "locale bridge maps en-US to en" do
    assert_equal :en, Brgen::LocaleBridge.resolve(:"en-US")
  end
end
