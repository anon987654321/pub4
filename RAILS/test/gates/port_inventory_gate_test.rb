# frozen_string_literal: true

require "fileutils"
require "minitest/autorun"
require "tmpdir"
require_relative "gate_probe_harness"
require_relative "../../../OPENBSD/gates/port_inventory"

# port_inventory moved to OPENBSD/gates on 2026-09-11 and kept its row in
# RAILS/gates/gates.yml, so its ROOT is now two levels up rather than three. Three
# gates broke on exactly that arithmetic during the move — one went looking for
# /Users/mac/Documents/GitHub/RAILS/apps.yml — and the fail-open runner called it
# errored rather than failed, which is the quietest way for a gate to stop
# guarding. The first test is that arithmetic.
#
# The rest plant the drift the gate exists to catch. Its checks all take the app
# list as an argument, so a disagreeing list is the defect: one app whose relayd
# port, crawl manifest or smoke probe no longer matches apps.yml. That is the real
# failure it was written for — a port changed everywhere except relayd.conf, where
# the deploy succeeds, rcctl reports the app running, and the site serves 502.
class PortInventoryGateTest < Minitest::Test
  include GateProbe

  GATE = Deploy::PortInventoryGate
  App = Deploy::Inventory::App

  def apps = Deploy::Inventory.new(root: GATE::ROOT).apps

  def moved(app, port:)
    App.new(**app.to_h.merge(port: port))
  end

  def findings(check, list)
    result = Deploy::GateResult.new
    GATE.new.send(check, result, list)
    result.failures
  end

  def test_its_root_is_the_repo_and_not_one_directory_past_it
    assert_equal File.expand_path("../../..", __dir__), GATE::ROOT
    assert_path_exists GATE::APPS_YML
    refute_empty apps, "the inventory reads nothing, so every check below would pass on an empty list"
  end

  # The third state. Every check reads the app list, so an empty list is not a
  # clean fleet — it is a gate with nothing to compare, and fourteen checks that
  # all vacuously pass. The gate says so instead.
  def test_an_inventory_that_lists_no_apps_is_inconclusive_rather_than_fourteen_vacuous_passes
    Dir.mktmpdir("port-inventory") do |root|
      FileUtils.mkdir_p(File.join(root, "RAILS"))
      File.write(File.join(root, "RAILS", "apps.yml"), "apps: {}\n")
      result = with_const(GATE, :ROOT, root) { GATE.run }

      assert_equal :inconclusive, result.outcome
      assert_match(/lists no apps — every check below reads that list/, result.unchecked.join(" | "))
      assert_equal 0, result.checks_ran
    end
  end

  # The one mirror that carries live traffic, and the one nothing checked until it
  # had already drifted.
  def test_a_relayd_port_that_no_longer_matches_apps_yml_is_named
    drifted = apps.map { |app| app.name == "brgen" ? moved(app, port: 39_999) : app }
    named = findings(:check_relayd_ports, drifted)

    assert_match(/brgen: relayd\.conf forwards to port \d+, apps\.yml says 39999/, named.join(" | "))
    assert_empty findings(:check_relayd_ports, apps), "the committed relayd.conf and apps.yml agree today"
  end

  def test_a_crawl_manifest_port_that_no_longer_matches_apps_yml_is_named
    drifted = apps.map { |app| app.name == "amber" ? moved(app, port: 39_998) : app }

    assert_match(/amber: crawl_manifest\.yml port \d+ must mirror apps\.yml 39998/,
                 findings(:check_crawl_manifest, drifted).join(" | "))
    assert_empty findings(:check_crawl_manifest, apps)
  end

  # A retired port here does not fail loudly. It reports the app down forever, or
  # reports a different app's health under this app's name once the number is
  # reused.
  def test_a_smoke_probe_naming_a_port_no_app_listens_on_is_named
    drifted = apps.map { |app| moved(app, port: app.port + 10_000) }
    named = findings(:check_smoke_probes, drifted).join(" | ")

    assert_match(/probes port \d{5}, which no app in apps\.yml listens on/, named)
    assert_empty findings(:check_smoke_probes, apps)
  end

  def test_two_apps_claiming_one_port_are_named
    first, second, = apps
    result = Deploy::GateResult.new
    GATE.new.send(:check_uniques, result, [first, moved(second, port: first.port)], :port)

    assert_match(/port collision #{first.port}: #{first.name}, #{second.name}/, result.failures.join(" | "))
  end

  # A file naming one port is using a number; a file naming the whole fleet is a
  # second inventory. Undeclared, it is how relayd.conf drifted unnoticed.
  def test_an_undeclared_file_stating_two_app_ports_is_named
    ports = apps.first(2).map(&:port)
    planted = "RAILS/test/gates/port_inventory_fleet_fixture.yml"
    path = File.join(GATE::ROOT, planted)
    File.write(path, ports.map { |port| "port: #{port}\n" }.join)

    assert_match(/#{Regexp.escape(planted)} states two or more app ports/,
                 findings(:check_fleet_inventories, apps).join(" | "))
  ensure
    FileUtils.rm_f(path)
  end

  def test_the_committed_tree_satisfies_every_check_it_declares
    result = GATE.run

    assert_equal :passed, result.outcome, result.failures.join("\n")
    assert_equal 14, result.checks_ran, "the check count is the gate's own claim about its reach"
  end
end
