# frozen_string_literal: true

require_relative "test_helper"

class TestExternalWorkMachine < Minitest::Test
  def setup
    @machine = Master::Core::Execution::ExternalWorkMachine.new(context: {})
  end

  def test_successful_run
    result = @machine.run(:deploy_app, { env: :production })
    assert_equal true, result.ok?
    assert_equal :completed, @machine.status
  end

  def test_preflight_failure
    # Mock preflight to fail
    @machine.define_singleton_method(:preflight) { |op, params| false }
    result = @machine.run(:deploy_app, {})
    assert_equal false, result.ok?
    assert_equal :preflight, @machine.status
  end

  def test_auth_failure
    @machine.define_singleton_method(:authenticate) { |op| false }
    result = @machine.run(:deploy_app, {})
    assert_equal false, result.ok?
    assert_equal :auth, @machine.status
  end

  def test_verification_failure
    @machine.define_singleton_method(:verify) { |op, res| Master::Result.err("verification failed") }
    result = @machine.run(:deploy_app, {})
    assert_equal false, result.ok?
    # It should fail during the verify stage
    assert_equal :verify, @machine.status
  end
end
