# frozen_string_literal: true

require "minitest/autorun"
# Every read below inspects UTF-8 source. Under a C locale -- which is how the
# weekly integrity run invokes these on vm23 -- Ruby defaults file reads to
# US-ASCII and each one raises "invalid byte sequence". Same require, same
# reason, as RAILS/gates/runner.rb.
require_relative "../lib/utf8"

class RestoreScriptsTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_restore_backups_is_litestream_restore
    source = File.read(File.join(ROOT, "restore_backups.sh"))
    assert_includes source, "litestream restore"
    assert_includes source, "extract_legacy_installers.sh"
    refute_includes source, "MASTER/RAILS"
  end

  def test_vps_deploy_stamps_head_after_the_work
    source = File.read(File.join(ROOT, "bin/vps-deploy"))
    assert_includes source, "write_stamp()"
    assert_includes source, 'sha=$(git -C "$repo" rev-parse --short HEAD)'
    # The read must live inside write_stamp, not above the master pull.
    write = source[ /write_stamp\(\) \{.*?\n\}/m ]
    assert write, "write_stamp function missing"
    assert_includes write, "rev-parse --short HEAD"
    refute_match(/sha=\$\(git -C "\$repo" rev-parse --short HEAD\)\nstarted=/, source.split("write_stamp()")[0])
    assert_includes source, "pull --ff-only origin main"
    assert_includes source, 'write_stamp master failed'
    assert_includes source, 'write_stamp "$app" failed'
  end

  def test_vps_ci_mirrors_the_tracked_tree_not_vendor
    source = File.read(File.join(ROOT, "vps_ci.sh"))
    assert_includes source, "git -C \"$repo\" archive HEAD RAILS"
    refute_includes source, 'doas tar cf - -C "$repo" RAILS'
    assert_includes source, "vendor/javascript"
    assert_includes source, "public"
  end

  def test_extract_legacy_installers_targets_top_level_rails
    source = File.read(File.join(ROOT, "extract_legacy_installers.sh"))
    assert_includes source, 'scripts_root="$ROOT_DIR/RAILS"'
    refute_includes source, "MASTER/RAILS"
  end
end
