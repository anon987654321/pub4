# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/result"
require_relative "../lib/stages/guard"

class TestGuard < Minitest::Test
  def setup
    @guard = MASTER::Stages::Guard.new
  end

  def test_allows_safe_commands
    result = @guard.call({ text: "ls -la" })
    assert result.ok?
  end

  def test_blocks_rm_rf_root
    result = @guard.call({ text: "rm -rf /" })
    assert result.err?
    assert_match(/Blocked/, result.error)
  end

  def test_blocks_dev_sda_redirect
    result = @guard.call({ text: "echo foo > /dev/sda" })
    assert result.err?
    assert_match(/Blocked/, result.error)
  end

  def test_blocks_drop_table
    result = @guard.call({ text: "DROP TABLE users" })
    assert result.err?
    assert_match(/Blocked/, result.error)
  end

  def test_blocks_format_command
    result = @guard.call({ text: "FORMAT C:" })
    assert result.err?
    assert_match(/Blocked/, result.error)
  end

  def test_blocks_mkfs
    result = @guard.call({ text: "mkfs.ext4 /dev/sdb1" })
    assert result.err?
    assert_match(/Blocked/, result.error)
  end

  def test_blocks_dd_if
    result = @guard.call({ text: "dd if=/dev/zero of=/dev/sda" })
    assert result.err?
    assert_match(/Blocked/, result.error)
  end

  def test_respects_upstream_block
    result = @guard.call({ text: "safe command", blocked: true })
    assert result.err?
    assert_match(/upstream/, result.error)
  end
end
