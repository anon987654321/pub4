# frozen_string_literal: true

require_relative "test_helper"
require "yaml"

class TestConstitutionTriage < Minitest::Test
  def test_buckets_scanner_self_and_rule_retune_findings
    triage = Master::Review::Scan::ConstitutionTriage.new(root: Master::ROOT)
    findings = [
      { rule: "SILENT_RESCUE", file: File.join(Master::ROOT, "lib/ground/config.rb") },
      { rule: "magic_number", file: File.join(Master::ROOT, "lib/ground/config.rb") },
      { rule: "SQL_INJECTION", file: File.join(Master::ROOT, "lib/review/scan/rules/yaml_bridge_rules.rb") },
      { rule: "SCAN_TIMEOUT", file: File.join(Master::ROOT, "lib/slow.rb") },
    ]

    buckets = triage.buckets(findings).to_h { |bucket| [bucket.name, bucket.findings.size] }

    assert_equal 1, buckets[:true_violation]
    assert_equal 1, buckets[:rule_retune]
    assert_equal 1, buckets[:scanner_self_reference]
    assert_equal 1, buckets[:timed_out]
  end

  # The reason this class was once deleted: RULE_RETUNE_IDS is a hand-copied list,
  # and an id that stops naming a rule keeps excusing findings that no longer
  # exist while looking like it excuses something. Eight of the original fifty had
  # rotted that way. EXEMPTIONS_EXPIRE says a check fails when the named thing
  # stops existing; this is that check.
  #
  # Three registries, because a rule id can come from any of them: the scanner's
  # own registry, data/rules.yml (where the lowercase ids live, as `- id:` rows
  # rather than keys), and law/.
  def test_every_retune_id_still_names_a_live_rule
    dead = Master::Review::Scan::ConstitutionTriage::RULE_RETUNE_IDS - live_rule_ids.to_a

    assert_empty dead,
                 "RULE_RETUNE_IDS names #{dead.size} rule(s) no registry defines: #{dead.join(', ')}. " \
                 "An exemption for a rule that does not exist excuses nothing — drop it or fix the spelling."
  end

  private

  def live_rule_ids
    ids = Set.new
    Master::Review::Scan::InfraHelpers.build_scanner(root: Master::ROOT).rules.each { |rule| ids << rule.id.to_s }
    collect_yaml_ids(YAML.unsafe_load_file(File.join(Master::ROOT, "data/rules.yml")), ids)
    Law.rules.each_key { |id| ids << id.to_s } if defined?(Law)
    ids
  end

  # rules.yml carries ids two ways: a `- id: name` row in a list, and a mapping
  # whose key is the id and whose body holds a `detect`.
  def collect_yaml_ids(node, ids)
    case node
    when Hash
      ids << node["id"].to_s if node["id"].is_a?(String)
      node.each do |key, value|
        ids << key.to_s if value.is_a?(Hash) && (value.key?("detect") || value.key?("pattern"))
        collect_yaml_ids(value, ids)
      end
    when Array
      node.each { |child| collect_yaml_ids(child, ids) }
    end
  end
end
