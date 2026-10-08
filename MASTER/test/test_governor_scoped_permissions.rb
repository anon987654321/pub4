# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/fix/governor"

class TestGovernorScopedPermissions < Minitest::Test
  Config = Struct.new(:auto?)

  # Dangerous requests that name doas, sudo or su are the ones the governor asks
  # a person about; without a TTY that ask is a refusal, so an undecided request
  # reads as refused and only a remembered decision lets one through.
  def setup
    @governor = Master::Fix::Governor.new(config: Config.new(false))
    @governor.instance_variable_set(:@prompt, nil) # no TTY, even when run from one
  end

  def test_always_allow_is_scoped_to_the_exact_request
    @governor.allow!("zsh", "doas git status")

    assert @governor.check_permit("zsh", :dangerous, "doas git status").ok?
    refute @governor.check_permit("zsh", :dangerous, "doas git push").ok?
  end

  def test_deny_is_scoped_and_survives_repeated_checks
    @governor.deny!("zsh", "doas git push")

    refute @governor.check_permit("zsh", :dangerous, "doas git push").ok?
    refute @governor.check_permit("zsh", :dangerous, "doas git push").ok?
    refute @governor.check_permit("zsh", :dangerous, "doas git status").ok?
  end

  def test_clear_decisions_removes_session_scoped_permissions
    @governor.allow!("zsh", "doas git status")
    assert @governor.check_permit("zsh", :dangerous, "doas git status").ok?

    @governor.clear_decisions!

    refute @governor.check_permit("zsh", :dangerous, "doas git status").ok?
  end
end
