# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/fix/governor"

class TestGovernorScopedPermissions < Minitest::Test
  Config = Struct.new(:auto?)

  def setup
    @governor = Master::Fix::Governor.new(config: Config.new(false))
  end

  def test_always_allow_is_scoped_to_the_exact_request
    @governor.allow!("zsh", "git status")

    assert @governor.check_permit("zsh", :dangerous, "git status").ok?
    refute @governor.check_permit("zsh", :dangerous, "git push").ok?
  end

  def test_deny_is_scoped_and_survives_repeated_checks
    @governor.deny!("zsh", "git push")

    refute @governor.check_permit("zsh", :dangerous, "git push").ok?
    refute @governor.check_permit("zsh", :dangerous, "git push").ok?
    refute @governor.check_permit("zsh", :dangerous, "git status").ok?
  end

  def test_clear_decisions_removes_session_scoped_permissions
    @governor.allow!("zsh", "git status")
    assert @governor.check_permit("zsh", :dangerous, "git status").ok?

    @governor.clear_decisions!

    refute @governor.check_permit("zsh", :dangerous, "git status").ok?
  end
end
