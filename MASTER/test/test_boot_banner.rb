# frozen_string_literal: true

require_relative "test_helper"
require "stringio"
require "open3"
require "rbconfig"

class TestBootBanner < Minitest::Test
  def test_print_is_silent_by_default
    ENV.delete("MASTER_BOOT_STATUS")
    io = StringIO.new
    Master::CLI::BootBanner.print(io:)
    assert_empty io.string
  end

  def test_print_emits_banner_lines_when_enabled
    ENV["MASTER_BOOT_STATUS"] = "1"
    io = StringIO.new
    Master::CLI::BootBanner.print(io:)
    assert_includes io.string, "boot0 at mainbus0: safe "
    assert_includes io.string, "master0: ready"
  ensure
    ENV.delete("MASTER_BOOT_STATUS")
  end

  def test_banner_lines_use_dmesg_unit_grammar
    lines = Master::CLI::BootBanner.banner_lines

    assert(lines.all? { |line| line.match?(/\A(?:[a-z]+\d+ at [a-z]+\d+: |[a-z]+\d+: )/) }, lines.inspect)
  end

  def test_banner_lines_reflect_env_flags
    lines = Master::CLI::BootBanner.banner_lines
    assert(lines.any? { |line| line.start_with?("boot0 at mainbus0: safe ") })
    assert(lines.any? { |line| line.start_with?("style0 at master0: ") })
  end

  # Regression: bin/cli's --boot-status flag set MASTER_BOOT_STATUS=1 but
  # nothing ever printed the banner, so the flag was completely inert. Its
  # units now attach inside the splash, in the device tree before "root on",
  # and the splash's "root on" is the only line that says the boot is done.
  def test_boot_status_units_attach_before_root_on
    lines = boot_status_splash
    boot = lines.index { |line| line.start_with?("boot0 at mainbus0: safe ") }
    root = lines.index { |line| line.start_with?("root on master0") }

    assert boot && root && boot < root, lines.inspect
    assert lines.first.start_with?("master0 at mainbus0: MASTER "), lines.first
    refute_includes lines, "master0: ready"
  end

  # As in the kernel, a unit attaches once and reports after as "unit: detail".
  def test_boot_status_splash_attaches_each_unit_once
    attached = boot_status_splash.filter_map { |line| line[/\A([a-z]+\d+) at /, 1] }

    assert_equal attached.uniq, attached
  end

  private

  def boot_status_splash
    ENV["MASTER_BOOT_STATUS"] = "1"
    Master::Voice::Renderer.new(config: {}).splash("claude-cli:claude-opus-5-5").lines(chomp: true)
  ensure
    ENV.delete("MASTER_BOOT_STATUS")
  end

  public

  def test_boot_has_no_ascii_wordmark_before_the_dmesg_lines
    source = File.read(File.join(Master::ROOT, "lib", "boot", "master_boot.rb"))
    refute_includes source, "CLI::BootBanner.wordmark"
    refute_respond_to Master::CLI::BootBanner, :wordmark
  end

  # `bin/master --help` prints usage without building the runtime. The option
  # parser ran only after Master.boot, so help cost a full boot and exited 1
  # whenever that boot raised. The banner prints on the way into the boot, so
  # its absence proves help returned first, whether or not a boot would succeed.
  def test_cli_help_returns_before_the_boot_banner
    master = File.join(Master::ROOT, "bin", "master")
    out, status = Open3.capture2e({ "MASTER_BOOT_STATUS" => "1" }, RbConfig.ruby, master, "--help",
                                  chdir: Master::ROOT, stdin_data: "")
    assert status.success?, "bin/master --help exited #{status.exitstatus}: #{out.lines.last(3).join}"
    assert_includes out, "Usage: bin/master"
    refute_includes out, "boot0 at mainbus0: safe", "bin/master --help started the boot"
  end

  # The Claude Code print-mode flags are parsed before the boot, so help can list
  # them and a permission mode can warn without building the runtime.
  def test_cli_help_lists_the_print_mode_flags
    master = File.join(Master::ROOT, "bin", "master")
    out, status = Open3.capture2e(RbConfig.ruby, master, "--permission-mode", "bypassPermissions", "--help",
                                  chdir: Master::ROOT, stdin_data: "")
    assert status.success?, "bin/master --help exited #{status.exitstatus}: #{out.lines.last(3).join}"
    %w[--model --output-format --permission-mode --allowedTools].each { |flag| assert_includes out, flag }
    assert_includes out, "bypasses nothing"
  end
end
