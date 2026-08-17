# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../gates/support/guest_flow_persona"
require_relative "../../../OPENBSD/lib/gate_result"

class GuestFlowPersonaTest < Minitest::Test
  def setup
    @persona = Deploy::GuestFlowPersona.new(port: 9_999)
  end

  def test_capabilities_defined
    %i[no_auth_wall has_main messenger_compose marketplace_browse marketplace_cart dating_browse].each do |cap|
      assert Deploy::GuestFlowPersona::CAPABILITIES.key?(cap), "missing capability #{cap}"
    end
  end

  def test_no_auth_wall_capability
    body = "<main id=\"main-content\">Messages</main>"
    findings = @persona.assert_capabilities(body, :no_auth_wall, :has_main, :messenger_compose, label: "messenger")
    assert_empty findings.map { |f| f[:message] }

    walled = body + "<p>Sign in to continue</p>"
    findings = @persona.assert_capabilities(walled, :no_auth_wall, label: "messenger")
    assert findings.any? { |f| f[:message].include?("auth wall") }
  end

  def test_missing_compose_fails_messenger
    body = "<main id=\"main-content\">Hello</main>"
    findings = @persona.assert_capabilities(body, :messenger_compose, label: "messenger")
    assert findings.any?
  end

  def test_run_probes_skips_when_port_closed
    result = Deploy::GateResult.new
    @persona.run_brgen_probes!(result, port_open: false)
    assert result.ok?
    assert result.warnings.any? { |w| w.include?("skipped") }
  end

  def test_brgen_probes_cover_guest_open_surfaces
    labels = Deploy::GuestFlowPersona::BRGEN_PROBES.map { |p| p[:label] }
    # "live" is not here: 76612fd0b folded /live into /nearby/room, so probing
    # it asserted live-feed markup against a redirect. The capability went with
    # it -- a rule nothing can reach is a rule that cannot fail.
    %w[home messenger marketplace marketplace_cart dating].each do |need|
      assert_includes labels, need
    end
  end
end
