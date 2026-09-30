# frozen_string_literal: true

require "minitest/autorun"
require_relative "../bin/vps-admin"

class VpsAdminTest < Minitest::Test
  def test_read_only_commands_are_named
    assert_equal [["doas", "df", "-h"]], OpenBSDAdmin.commands_for(["disk"])
    assert_equal [["doas", "pfctl", "-si"]], OpenBSDAdmin.commands_for(["pf", "status"])
    assert_equal [["doas", "syspatch", "-c"]], OpenBSDAdmin.commands_for(["updates"])
    assert_equal [["doas", "pkg_info"]], OpenBSDAdmin.commands_for(["packages"])
    assert_equal [["doas", "sysupgrade", "-n"]], OpenBSDAdmin.commands_for(["upgrade", "stage"])
  end

  def test_service_actions_are_allowlisted
    assert_equal [["doas", "rcctl", "restart", "master"]],
                 OpenBSDAdmin.commands_for(["service", "master", "restart"])
    assert_raises(ArgumentError) { OpenBSDAdmin.commands_for(["service", "master", "shell"]) }
    assert_raises(ArgumentError) { OpenBSDAdmin.commands_for(["service", "master;touch /tmp/x", "restart"]) }
  end

  def test_firewall_reload_validates_before_loading
    assert_equal(
      [["doas", "pfctl", "-nf", "/etc/pf.conf"], ["doas", "pfctl", "-f", "/etc/pf.conf"]],
      OpenBSDAdmin.commands_for(["pf", "reload"]),
    )
  end

  def test_arbitrary_commands_are_refused
    assert_raises(ArgumentError) { OpenBSDAdmin.commands_for(["sh", "-c", "id"]) }
    assert_raises(ArgumentError) { OpenBSDAdmin.commands_for(["service", "master", "exec", "id"]) }
  end

  def test_reboot_is_one_explicit_action
    assert_equal [["doas", "/sbin/reboot"]], OpenBSDAdmin.commands_for(["reboot"])
  end

  def test_status_is_composed_of_named_commands
    commands = OpenBSDAdmin.commands_for(["status"])
    assert_includes commands, ["hostname"]
    assert_includes commands, ["uptime"]
    assert_includes commands, ["uname", "-a"]
    assert_includes commands, ["doas", "df", "-h"]
  end
end
