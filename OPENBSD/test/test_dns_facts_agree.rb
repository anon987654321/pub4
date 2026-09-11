# frozen_string_literal: true

require "minitest/autorun"
require "yaml"

# Four DNS facts were written down twice: data/dns.yml declares them, OPERATOR.sh
# restates them as shell literals, and gates/dns_zones.rb had its own third copy
# of two. The copies had already drifted — OPERATOR.sh's resolver list led with
# 8.8.8.8 while the gate used Cloudflare and Quad9 and had written down why.
#
# The gate now reads the policy file. OPERATOR.sh cannot: that block is sourced
# before anything else runs, and making the deploy script shell out to ruby34 to
# boot would put it behind an interpreter it is itself responsible for
# installing. So the duplication stays and this makes it cost something.
class DnsFactsAgreeTest < Minitest::Test
  OPENBSD = File.expand_path("..", __dir__)
  POLICY = YAML.safe_load_file(File.join(OPENBSD, "data", "dns.yml"))
  OPERATOR = File.read(File.join(OPENBSD, "OPERATOR.sh"), encoding: "UTF-8")

  def shell_scalar(name)
    OPERATOR[/^typeset -r #{name}="([^"]+)"/, 1]
  end

  def shell_array(name)
    OPERATOR[/^typeset -a #{name}=\(([^)]*)\)/, 1]&.split
  end

  def test_brgen_ip_is_the_nameserver_the_policy_declares
    assert_equal POLICY.fetch("nameserver").fetch("ip"), shell_scalar("BRGEN_IP")
  end

  # ns.hyp.net is Domeneshop's secondary and pulls by AXFR, so it is the first
  # peer the policy lists rather than a separate fact.
  def test_hyp_ip_is_the_first_transfer_peer
    assert_equal POLICY.fetch("xfr_peers").first, shell_scalar("HYP_IP")
  end

  def test_the_public_resolvers_are_one_list
    assert_equal POLICY.fetch("resolvers").fetch("public"), shell_array("PUBLIC_RESOLVERS")
  end

  # If the two readers above stop finding anything, every assertion passes by
  # comparing nil to nil.
  def test_the_scan_reads_real_values
    refute_nil shell_scalar("BRGEN_IP"), "the typeset scan found no BRGEN_IP"
    refute_nil shell_array("PUBLIC_RESOLVERS"), "the typeset scan found no PUBLIC_RESOLVERS"
    refute_empty POLICY.fetch("resolvers").fetch("public")
  end
end
