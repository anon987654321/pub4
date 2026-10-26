# frozen_string_literal: true

require "minitest/autorun"
require "master"
require_relative "../lib/operator/services"

class OperatorServicesTest < Minitest::Test
  def test_status_has_named_subsystems
    status = Master::Operator.status
    assert_equal %w[cognition mission model memory device voice web], status.keys
  end

  # One vocabulary: a status opens with a HEALTH word, and ready only where something was observed.
  def test_every_status_speaks_the_one_health_vocabulary
    Master::Operator.status.each do |service, state|
      assert_includes Master::Operator::HEALTH, state.split(":").first, "#{service}: #{state}"
    end
    refute_match(/\Aready/, Master::Operator.state("memory"), "nothing probes memory, so it cannot read ready")
  end

  def test_security_reports_the_current_capability_grammar
    security = Master::Operator.security
    assert_equal :fix, security[:capability_profile]
    assert security[:monotonic_reduction]
    assert_equal "proposal-only", security[:model_authority]
  end

  def test_os_service_control_is_closed_to_master_stop_and_restart
    assert_raises(Master::SecurityError) { Master::Operator.run_rcctl("enable", "master") }
    assert_raises(Master::SecurityError) { Master::Operator.run_rcctl("restart", "relayd") }
    assert_raises(Master::SecurityError) { Master::Operator.run_rcctl("stop", "brgen") }
  end
  def test_embedded_services_cannot_be_stopped_as_if_they_were_rcctl_daemons
    assert_raises(ArgumentError) { Master::Operator.stop("cognition") }
    assert_raises(ArgumentError) { Master::Operator.restart("memory") }
  end
end
