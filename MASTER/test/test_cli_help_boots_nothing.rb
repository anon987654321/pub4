# frozen_string_literal: true

require_relative "test_helper"
require "open3"
require "rbconfig"

# `bin/cli --help` must print usage without building the runtime. The option
# parser ran only after Master.boot, so help took a full boot — seven seconds
# here — and exited 1 whenever the boot itself raised.
class TestCliHelpBootsNothing < Minitest::Test
  CLI = File.join(Master::ROOT, "bin", "cli")

  def test_help_prints_usage_and_exits_zero_without_booting
    # The boot banner prints on the way into Master.boot, so its absence is the
    # proof that help returned first, whether or not a boot would have succeeded.
    out, status = Open3.capture2e({ "MASTER_BOOT_STATUS" => "1" }, RbConfig.ruby, CLI, "--help",
                                  chdir: Master::ROOT, stdin_data: "")
    assert status.success?, "bin/cli --help exited #{status.exitstatus}: #{out.lines.last(3).join}"
    assert_includes out, "Usage: bin/cli"
    refute_includes out, "master: boot", "bin/cli --help started the boot"
  end
end
