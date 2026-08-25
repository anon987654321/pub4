# frozen_string_literal: true

require "minitest/autorun"
require "json"

# dns_zones gained a check that asks a public resolver whether the app domains
# point at us, which is a different question from the one it already asked —
# that check queries 46.23.89.226 directly, and our nameserver answers for
# every zone it serves whether or not anything delegates to it.
#
# bsdports.org is what the difference looks like. Registered to us at
# Domeneshop through 2027-08-08, relayd holding a keypair and a Host match, a
# valid certificate on disk to Nov 10 2026, RUNBOOK.md naming
# https://bsdports.org as its URL, rcctl reporting ok and the app answering 200
# on 47312 — and the .org registry delegating the name to
# ns1/2/3.expireddomain.hyp.net, Domeneshop's parking servers, which publish no
# A record. Publicly unreachable, with every check we had reporting fine.
#
# What this file guards is the population, not the lookup. The check reads
# OPENBSD/deploy_inventory.json, and a parse failure or a renamed key makes it
# return [] and pass having measured nothing — the failure mode this repo keeps
# finding. The network half belongs to the gate.
class DnsDelegationTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  INVENTORY = File.join(ROOT, "..", "OPENBSD", "deploy_inventory.json")
  GATE = File.join(ROOT, "gates", "lib", "host", "dns_zones.rb")

  def apps
    @apps ||= JSON.parse(File.read(INVENTORY)).fetch("apps", [])
  end

  def test_the_inventory_is_where_the_gate_looks
    assert File.exist?(INVENTORY), "deploy_inventory.json moved; the delegation check reads []"
    refute_empty apps, "no apps in the inventory — the check would pass having measured nothing"
  end

  def test_every_app_declares_a_domain
    undeclared = apps.reject { |app| app["domain"].to_s.include?(".") }

    assert_empty undeclared.map { |app| app["name"] },
                 "an app with no domain is skipped by the delegation check and cannot be found dark"
  end

  def test_all_three_apps_are_covered
    names = apps.map { |app| app["name"] }.sort

    assert_equal %w[amber brgen bsdports], names,
                 "the app set changed; the delegation check covers whatever is here, so confirm that is intended"
  end

  # The two questions have to stay distinct. If someone points the new check at
  # NAMESERVER it becomes a slower copy of nameserver_answers and stops being
  # able to see a parked delegation at all.
  def test_the_delegation_check_asks_a_public_resolver
    source = File.read(GATE)

    assert_match(/PUBLIC_RESOLVERS\s*=/, source, "the delegation check has no public resolver constant")
    assert_match(/nameserver: PUBLIC_RESOLVERS/, source,
                 "the delegation check must not query our own nameserver — that is the other check")
    assert_match(/def app_domains_delegate_to_us/, source, "the delegation check is gone")
  end
end
