# frozen_string_literal: true

require "minitest/autorun"

class RestoreScriptsTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_restore_backups_is_litestream_restore
    source = File.read(File.join(ROOT, "restore_backups.sh"))
    assert_includes source, "litestream restore"
    assert_includes source, "extract_legacy_installers.sh"
    refute_includes source, "MASTER/RAILS"
  end

  def test_extract_legacy_installers_targets_top_level_rails
    source = File.read(File.join(ROOT, "extract_legacy_installers.sh"))
    assert_includes source, 'scripts_root="$ROOT_DIR/RAILS"'
    refute_includes source, "MASTER/RAILS"
  end
end
