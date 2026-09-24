# frozen_string_literal: true

require "json"
require "minitest/autorun"
require_relative "../shared/lib/shared/mobile_app_registry"
require_relative "../shared/lib/shared/mobile_ios_project"

class MobileAppRegistryTest < Minitest::Test
  REGISTRY = Shared::MobileAppRegistry

  def test_registry_contains_core_verticals_and_amber
    keys = REGISTRY.all.map(&:key)

    assert_includes keys, :brgen
    assert_includes keys, :radio
    assert_includes keys, :dating
    assert_includes keys, :tv
    assert_includes keys, :takeaway
    assert_includes keys, :marketplace
    assert_includes keys, :maps
    assert_includes keys, :messenger
    assert_includes keys, :amber
  end

  def test_vertical_hosts_are_distinct_store_origins
    hosts = REGISTRY.all.map(&:host)

    assert_equal hosts.uniq.size, hosts.size
    assert_equal "brgen.no", REGISTRY.fetch(:brgen).host
    assert_equal "radio.brgen.no", REGISTRY.fetch(:radio).host
    assert_equal "markedsplass.brgen.no", REGISTRY.fetch(:marketplace).host
    assert_equal "amber.fashion", REGISTRY.fetch(:amber).host
  end

  def test_host_lookup_ignores_port_and_trailing_dot
    assert_equal :brgen, REGISTRY.for_host("BRGEN.NO:443").key
    assert_equal :amber, REGISTRY.for_host("amber.fashion.").key
  end

  def test_registry_covers_every_brgen_store_product_and_amber
    assert_equal %i[brgen radio dating tv takeaway marketplace maps messenger amber],
                 REGISTRY.all.map(&:key)
  end

  def test_ios_project_spec_is_generated_from_the_registry
    spec = Shared::MobileIosProject.spec

    assert_equal REGISTRY.all.map { |app| app.key.to_s.split("_").map(&:capitalize).join },
                 spec.fetch("configs").keys

    REGISTRY.all.each do |app|
      config = spec.fetch("targets").fetch("Pub4Mobile").fetch("settings").fetch("configs").fetch(
        app.key.to_s.split("_").map(&:capitalize).join
      )

      assert_equal app.ios_bundle_id, config.fetch("PRODUCT_BUNDLE_IDENTIFIER")
      assert_equal app.url, config.fetch("MOBILE_APP_URL")
      assert_equal app.host, config.fetch("MOBILE_APP_HOST")
      assert_equal app.name, config.fetch("MOBILE_APP_NAME")
    end
  end

  def test_each_product_has_a_web_origin_android_package_and_ios_bundle
    REGISTRY.all.each do |app|
      assert_match(%r{\Ahttps://}, app.url)
      refute_empty app.android_package
      refute_empty app.ios_bundle_id
      refute_equal app.host, app.android_package
      refute_equal app.host, app.ios_bundle_id
    end
  end

  def test_assetlinks_is_empty_until_a_real_signing_fingerprint_exists
    previous = ENV.delete("BRGEN_ANDROID_CERT_SHA256")

    begin
      assert_equal "[]\n", REGISTRY.assetlinks_json("brgen.no")
    ensure
      ENV["BRGEN_ANDROID_CERT_SHA256"] = previous if previous
    end
  end

  def test_assetlinks_uses_the_exact_package_and_configured_fingerprint
    previous = ENV["BRGEN_ANDROID_CERT_SHA256"]
    ENV["BRGEN_ANDROID_CERT_SHA256"] = "AA:BB,CC:DD"

    begin
      body = JSON.parse(REGISTRY.assetlinks_json("brgen.no"))

      assert_equal ["delegate_permission/common.handle_all_urls"], body.fetch(0).fetch("relation")
      target = body.fetch(0).fetch("target")
      assert_equal "android_app", target.fetch("namespace")
      assert_equal "no.brgen.brgen", target.fetch("package_name")
      assert_equal ["AA:BB", "CC:DD"], target.fetch("sha256_cert_fingerprints")
    ensure
      ENV["BRGEN_ANDROID_CERT_SHA256"] = previous if previous
    end
  end

  def test_apple_association_is_empty_until_the_team_id_exists
    previous = ENV.delete("APPLE_TEAM_ID")

    begin
      body = JSON.parse(REGISTRY.apple_app_site_association("amber.fashion"))

      assert_equal [], body.fetch("applinks").fetch("details")
    ensure
      ENV["APPLE_TEAM_ID"] = previous if previous
    end
  end

  def test_apple_association_uses_the_exact_team_and_bundle_id
    previous = ENV["APPLE_TEAM_ID"]
    ENV["APPLE_TEAM_ID"] = "TEAM123"

    begin
      body = JSON.parse(REGISTRY.apple_app_site_association("amber.fashion"))
      detail = body.fetch("applinks").fetch("details").fetch(0)

      assert_equal "TEAM123.fashion.amber.app", detail.fetch("appID")
      assert_equal ["*"], detail.fetch("paths")
    ensure
      ENV["APPLE_TEAM_ID"] = previous
    end
  end
end
