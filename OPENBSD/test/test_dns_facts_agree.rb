# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "yaml"
require_relative "../bin/render_dns"

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

  # The domain list is read twice as well, and not in two files but in two
  # languages. OPERATOR.sh's loops walk ALL_DOMAINS as zsh expands the array;
  # render_dns.rb splits the same block into lines. A comment, a quoted entry or
  # two entries on one line inside it splits differently, and then the zones the
  # generator writes and the domains the installer walks are two fleets. zsh
  # evaluates the block here so the two readings are compared, not assumed.
  def test_all_domains_reads_the_same_in_zsh_and_in_render_dns
    block = OPERATOR[/^ALL_DOMAINS=\(\n.*?\n\)$/m]
    refute_nil block, "no ALL_DOMAINS block in OPERATOR.sh"

    out, status = Open3.capture2("zsh", "-f", "-c", "#{block}\nprint -rl -- $ALL_DOMAINS")
    assert status.success?, "zsh could not evaluate the ALL_DOMAINS block"
    expanded = out.lines.to_h do |entry|
      domain, subs = entry.chomp.split(":", 2)
      [domain, subs.to_s.split(",").map(&:strip).reject(&:empty?)]
    end

    assert_operator expanded.size, :>, 40, "zsh expanded only #{expanded.size} domains"
    assert_equal expanded, RenderDns.city_zones
  end

  # If the two readers above stop finding anything, every assertion passes by
  # comparing nil to nil.
  def test_the_scan_reads_real_values
    refute_nil shell_scalar("BRGEN_IP"), "the typeset scan found no BRGEN_IP"
    refute_nil shell_array("PUBLIC_RESOLVERS"), "the typeset scan found no PUBLIC_RESOLVERS"
    refute_empty POLICY.fetch("resolvers").fetch("public")
  end
end

require_relative "../gates/dns_zones"
require_relative "../gates/domain_alignment"
require_relative "../bin/domain_watch"

# domain_watch asks the registry about every zone the policy declares, including
# one not yet rendered into nsd.conf.
class DomainWatchPopulationTest < Minitest::Test
  def test_a_zone_the_policy_declares_is_watched_before_nsd_conf_has_it
    original = RenderDns.method(:zones)
    RenderDns.define_singleton_method(:zones) { original.call.merge("ghost.example" => []) }

    assert_includes Deploy::DomainWatch.zones, "ghost.example"
  ensure
    RenderDns.define_singleton_method(:zones, original)
  end

  def test_the_watched_zones_are_the_rendered_zones
    assert_equal RenderDns.zones.keys.sort, Deploy::DomainWatch.zones
    assert_operator Deploy::DomainWatch.zones.size, :>, 40
  end
end

# The two gates that hold those facts to the zones and the registry, each beside
# the drift it exists to catch (decision 2026-08-22). The network half of
# dns_zones is handed a resolver that answers what the fixture says, so the
# verdict is the gate's and no packet leaves the machine.
class DnsZonesGateFixtureTest < Minitest::Test
  GATE = Deploy::DnsZonesGate

  # A resolver whose every name answers `addresses`, or raises `error`.
  Resolver = Struct.new(:addresses, :error) do
    def getaddresses(_name) = error ? raise(error) : addresses
    def getaddress(_name) = error ? raise(error) : addresses.first
  end

  def gate
    @gate ||= GATE.new.tap { |g| g.instance_variable_set(:@result, Deploy::GateResult.new) }
  end

  def result = gate.instance_variable_get(:@result)

  # RenderDns answers `name` with `replacement` applied to its real answer while
  # the gate runs `check`.
  def with_render(name, replacement, check)
    original = RenderDns.method(name)
    RenderDns.define_singleton_method(name) { replacement.call(original.call) }
    gate.send(check)
  ensure
    RenderDns.define_singleton_method(name, original)
  end

  # bsdports.org, owned and paid and parked at the registrar.
  def test_an_app_domain_that_resolves_nowhere_fails
    gate.send(:check_delegation, Resolver.new([]), "bsdports", "bsdports.org")

    assert_match(/bsdports\.org \(bsdports\) resolves nowhere/, result.failures.join)
  end

  def test_an_app_domain_delegated_somewhere_else_fails
    gate.send(:check_delegation, Resolver.new(["192.0.2.1"]), "brgen", "brgen.no")

    assert_match(/resolves to 192\.0\.2\.1, not #{Regexp.escape(GATE::NAMESERVER)}/, result.failures.join)
  end

  def test_an_app_domain_pointing_here_passes_and_counts
    gate.send(:check_delegation, Resolver.new([GATE::NAMESERVER]), "brgen", "brgen.no")

    assert_empty result.failures
    assert_equal 1, result.checks_ran
  end

  # A dropped packet is not a missing record: three timeouts skip, three
  # NXDOMAINs fail.
  def test_a_vertical_our_nameserver_does_not_answer_fails_and_a_timeout_only_skips
    gate.send(:check_domain, Resolver.new(nil, Resolv::ResolvError), "brgen.no", %w[tv])

    assert_match(/does not answer for brgen\.no, tv\.brgen\.no, www\.brgen\.no/, result.failures.join)

    timed_out = GATE.new.tap { |g| g.instance_variable_set(:@result, Deploy::GateResult.new) }
    timed_out.send(:check_domain, Resolver.new(nil, Resolv::ResolvTimeout), "brgen.no", %w[tv])
    outcome = timed_out.instance_variable_get(:@result)

    assert_empty outcome.failures
    assert_equal 1, outcome.live_skips
  end

  def test_a_domain_with_no_zone_block_in_nsd_conf_fails
    with_render(:zones, ->(zones) { zones.merge("ghost.example" => []) }, :every_domain_has_a_zone)

    assert_match(/nsd\.conf has no zone block for ghost\.example/, result.failures.join)
  end

  # The hand-edit the generator exists to stop: nsd.conf on disk is no longer
  # what data/dns.yml renders.
  def test_an_nsd_conf_the_generator_would_not_write_fails
    with_render(:nsd_conf_body, ->(body) { "#{body}# hand-edited\n" }, :generated_output_matches)

    assert_match(/generated file\(s\) differ .*nsd\.conf/, result.failures.join)
  end

  def test_the_committed_zones_match_what_the_generator_renders
    gate.send(:generated_output_matches)
    gate.send(:every_domain_has_a_zone)

    assert_empty result.failures
    assert_operator result.checks_ran, :>, 50
  end
end

class DomainAlignmentGateFixtureTest < Minitest::Test
  GATE = Deploy::DomainAlignmentGate

  def setup
    @gate = GATE.new
    @registry = @gate.send(:parse_registry_entries).keys
    @keys = @gate.send(:parse_relayd_keypairs)
    @declared = @gate.send(:extract_constant, GATE::REGISTRY.read, "LIVE_DOMAINS")
  end

  def alignment_failures(keys)
    result = Deploy::GateResult.new
    @gate.send(:live_domains_check, result, @registry, keys)
    result.failures.join(" | ")
  end

  # Too many: the city network links a hostname relayd holds no certificate for.
  def test_a_live_domain_with_no_keypair_fails
    assert_match(/LIVE_DOMAINS names #{Regexp.escape(@declared.last)} with no tls keypair/,
                 alignment_failures(@keys - [@declared.last]))
  end

  # Too few: a city relayd serves and nothing links.
  def test_a_certified_city_left_out_of_live_domains_fails
    unlisted = (@registry - @declared).first

    refute_nil unlisted, "every registry domain is live, so this fixture has nothing to plant"
    assert_match(/LIVE_DOMAINS omits #{Regexp.escape(unlisted)}/, alignment_failures(@keys + [unlisted]))
  end

  # A commented-out keypair is a certificate relayd does not load, so the city it
  # names is linked with nothing serving it.
  def test_a_commented_out_keypair_does_not_count_as_live
    commented = GATE::RELAYD.read.sub(/^(\s*)(tls keypair "#{Regexp.escape(@declared.last)}")/, '\1# \2')
    keys = @gate.send(:parse_relayd_keypairs, commented)

    refute_includes keys, @declared.last
    assert_equal @keys.size - 1, keys.size
    assert_match(/LIVE_DOMAINS names #{Regexp.escape(@declared.last)} with no tls keypair/, alignment_failures(keys))
  end

  # The gate compares the registry against the fleet render_dns writes zones for,
  # and the zsh expansion test above holds that reader to OPERATOR.sh.
  def test_the_gate_reads_all_domains_through_render_dns
    original = RenderDns.method(:city_zones)
    RenderDns.define_singleton_method(:city_zones) { original.call.except("brgen.no") }

    assert_match(/missing DNS brgen\.no/, GATE.run.failures.join(" | "))
  ensure
    RenderDns.define_singleton_method(:city_zones, original)
  end

  def test_the_committed_tree_passes
    result = GATE.run

    assert_equal :passed, result.outcome, result.failures.join("\n")
    assert_equal @declared.size, result.checks_ran
  end
end
