# frozen_string_literal: true

require "minitest/autorun"
require "master"
require_relative "../lib/operator/services"

class OperatorServicesTest < Minitest::Test
  def test_status_has_named_subsystems
    status = Master::Operator.status
    assert_equal %w[cognition mission model memory device voice web], status.keys
  end

  def test_security_reports_the_current_capability_grammar
    security = Master::Operator.security
    assert_equal :fix, security[:capability_profile]
    assert security[:monotonic_reduction]
    assert_equal "proposal-only", security[:model_authority]
  end

  def test_embedded_services_cannot_be_stopped_as_if_they_were_rcctl_daemons
    assert_raises(ArgumentError) { Master::Operator.stop("cognition") }
    assert_raises(ArgumentError) { Master::Operator.restart("memory") }
  end
end
