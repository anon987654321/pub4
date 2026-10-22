# frozen_string_literal: true

require_relative "test_helper"
require_relative "../tools/rails/crawl_support"

class CrawlSupportTest < Minitest::Test
  REPO_ROOT = File.expand_path("../..", __dir__)

  def test_crawler_inventories_resolve_to_the_canonical_rails_files
    assert_equal File.join(REPO_ROOT, "RAILS", "crawl_manifest.yml"), CrawlSupport::MANIFEST
    assert_equal File.join(REPO_ROOT, "RAILS", "apps.yml"), CrawlSupport::APPS_YML
    assert_equal File.join(REPO_ROOT, "OPENBSD", "deploy_inventory.json"), CrawlSupport::DEPLOY_INVENTORY

    assert_kind_of Hash, CrawlSupport.load_manifest
    assert_kind_of Hash, CrawlSupport.load_apps_yml
    assert_kind_of Hash, CrawlSupport.load_master_json
  end

  def test_optional_crawler_reuses_the_live_checks_transport
    check_path = File.join(Master::ROOT, "checks", "support", "crawl_support.rb")
    crawler_path = File.join(Master::ROOT, "tools", "rails", "crawl_support.rb")
    check_source = File.read(check_path, encoding: "UTF-8")
    crawler_source = File.read(crawler_path, encoding: "UTF-8")

    assert_includes crawler_source, 'require_relative "../../checks/support/crawl_support"'
    assert_match(/^\s*def fetch\(/, check_source)
    assert_match(/^\s*def port_open\?\(/, check_source)
    assert_match(/on_error:/, check_source)
    assert_match(/^\s*def crawler_port_open\?\(/, crawler_source)
    refute_match(/^\s*def fetch\(/, crawler_source)
    refute_match(/^\s*def port_open\?\(/, crawler_source)
  end

  def test_shared_port_probe_reports_optional_diagnostics_without_masking_failure
    reported = nil
    error = Errno::ECONNREFUSED.new("fixture refused")

    Socket.stub(:tcp, ->(*, **) { raise error }) do
      refute CrawlSupport.port_open?(
        "127.0.0.1", 9, on_error: ->(failure) { reported = failure }
      )
    end

    assert_same error, reported
  end
end
