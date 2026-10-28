# frozen_string_literal: true

require_relative "test_helper"

class TestIngressJobs < Minitest::Test
  def test_lookup_cron_self_test
    job = Master::Io::IngressJobs.lookup_cron("self_test")
    assert job
    assert_equal "cron", job["kind"]
  end

  def test_untrusted_ingress_cannot_dispatch_privileged_slash_commands
    gateway = Master::Io::Gateway.new(pipeline: nil, session: nil, container: { commands: {} })
    ["/fix", "/commit", "/deploy master --confirm", "/pair revoke subject"].each do |message|
      dispatched = false
      result = nil
      Master::CLI::TurnRouter.stub(:dispatch_slash, ->(*) {
        dispatched = true
        Master::Result.ok({ rendered: "unexpected dispatch" })
      }) do
        result = Master::Io::IngressRunner.run_turn(
          container: { gateway: }, message:, metadata: { trust: :untrusted }, elevated: false,
        )
      end
      assert result.err?, "#{message} should be refused"
      assert_equal :policy, result.category
      assert_match(/visitors/i, result.message.to_s)
      refute dispatched, "#{message} reached command dispatch"
    end
  end

  def test_elevated_ingress_still_reaches_command_dispatch
    gateway = Master::Io::Gateway.new(pipeline: nil, session: nil, container: { commands: {} })
    dispatched = false
    Master::CLI::TurnRouter.stub(:dispatch_slash, ->(*) {
      dispatched = true
      Master::Result.ok({ rendered: "owner path" })
    }) do
      result = Master::Io::IngressRunner.run_turn(
        container: { gateway: }, message: "/fix", metadata: { trust: :owner }, elevated: true,
      )
      assert result.ok?, -> { result.message.to_s }
    end
    assert dispatched, "elevated ingress must retain command access"
  end
end
