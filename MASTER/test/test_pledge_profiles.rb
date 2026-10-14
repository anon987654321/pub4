# frozen_string_literal: true

require "minitest/autorun"
require "master"

class PledgeProfileTest < Minitest::Test
  def test_profiles_have_declared_capabilities
    expected = {
      boot: %i[stdio read execute],
      model: %i[stdio read model],
      fix: %i[stdio read write create execute],
      device: %i[stdio read device],
      world: %i[stdio read world],
    }

    expected.each do |name, capabilities|
      profile = Master::Ground::Pledge.profile(name)
      assert_equal capabilities, profile.capabilities
      refute_empty profile.promises
    end
  end

  def test_profile_constructor_normalizes_values
    profile = Master::Ground::Pledge::Profile.new(
      name: "fix",
      capabilities: %w[stdio write],
      promises: +"stdio rpath",
    )

    assert_equal :fix, profile.name
    assert_equal %i[stdio write], profile.capabilities
    assert_equal "stdio rpath", profile.promises
    assert profile.capabilities.frozen?
    assert profile.promises.frozen?
  end

  def test_security_syscall_failures_are_not_reported_as_success
    pledge = Master::Ground::Pledge

    assert_equal 0, pledge.checked_syscall!("unveil", 0)
    error = assert_raises(SystemCallError) do
      pledge.checked_syscall!("unveil", -1, Errno::EPERM::Errno)
    end
    assert_equal Errno::EPERM::Errno, error.errno
    assert_match(/unveil/, error.message)
  end

  def test_unveil_lock_checks_the_kernel_result
    source = File.read(File.expand_path("../lib/ground/pledge.rb", __dir__))

    assert_match(
      /def lock_unveil!\s+checked_syscall!\("unveil", LibC\.unveil\(Fiddle::NULL, Fiddle::NULL\), Fiddle\.last_error\)/,
      source
    )
  end

  def test_trusted_boot_does_not_set_execpromises_globally
    pledge = Master::Ground::Pledge
    calls = []

    pledge.stub(:pledge, ->(promises, execpromises = nil) { calls << [promises, execpromises] }) do
      pledge.stub(:unveil, ->(*) {}) do
        pledge.stub(:lock_unveil!, -> {}) do
          pledge.stage1_boot!(Dir.pwd)
          pledge.stage2_lock!
        end
      end
    end

    assert_equal [
      [pledge::STAGE1_PROMISES, nil],
      [pledge::STAGE2_PROMISES, nil],
    ], calls
  end

  def test_exec_worker_sets_execpromises_before_the_command
    source = File.read(File.expand_path("../bin/cli", __dir__))

    assert_operator source.index('if ARGV.first == "--exec-worker"'), :<,
                    source.index('require_relative "../lib/boot/entrypoint"')
    assert_includes source, "guard.pledge(guard::STAGE2_PROMISES, guard::EXEC_PROMISES)"
    assert_includes source, "def prepare_exec_worker_load_path"
    assert_includes source, 'gem_root = File.join(RbConfig::CONFIG.fetch("libdir"), "ruby", "gems",'
    assert_includes Master::Ground::Pledge::EXEC_PROMISES.split, "exec"
    refute_includes Master::Ground::Pledge::EXEC_PROMISES.split, "unveil"
  end

  def test_unknown_profile_is_rejected
    assert_raises(KeyError) { Master::Ground::Pledge.profile(:unknown) }
  end
end
