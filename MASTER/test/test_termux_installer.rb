# frozen_string_literal: true

require "minitest/autorun"
require "open3"

class TermuxInstallerTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SCRIPT = File.join(ROOT, "tools", "device", "termux", "install.sh")

  def source = File.read(SCRIPT)

  def test_installer_rejects_non_termux_shells
    assert_match(%r{#!/data/data/com\.termux/files/usr/bin/bash}, source)
    assert_match(/Run this inside Termux/, source)
  end

  def test_existing_checkout_origin_is_validated_before_running_project_code
    assert_match(/remote get-url origin/, source)
    assert_match(/refusing to run its installer/, source)
    assert_operator source.index("remote get-url origin"), :<, source.index('cd "$ROOT/MASTER"')
  end

  def test_never_uses_android_shared_storage_for_installation
    refute_match(%r{/storage/emulated/0|/sdcard}, source)
    assert_includes source, 'ROOT="${HOME}/pub4"'
  end

  def test_launcher_forwards_arguments_without_shell_interpolation
    assert_includes source, 'exec ruby bin/cli "$@"'
  end

  def test_script_has_valid_bash_syntax
    skip "bash unavailable" unless system("command -v bash >/dev/null 2>&1")

    output, status = Open3.capture2e("bash", "-n", SCRIPT)
    assert status.success?, output
  end
end
