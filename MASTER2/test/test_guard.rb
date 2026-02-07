# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/master"

class TestGuard < Minitest::Test
  def setup
    MASTER::DB.setup(path: ":memory:")
    @stage = MASTER::Stages::Guard.new
  end

  def test_blocks_rm_rf_slash
    result = @stage.call({ text: "rm -rf /" })
    refute result.ok?
    assert_match(/Blocked: dangerous pattern detected/, result.error)
  end

  def test_blocks_rm_rf_with_space
    result = @stage.call({ text: "rm -r /" })
    refute result.ok?
    assert_match(/Blocked: dangerous pattern detected/, result.error)
  end

  def test_blocks_dev_sda
    result = @stage.call({ text: "cat file > /dev/sda" })
    refute result.ok?
    assert_match(/Blocked: dangerous pattern detected/, result.error)
  end

  def test_blocks_dev_hda
    result = @stage.call({ text: "echo data > /dev/hda" })
    refute result.ok?
    assert_match(/Blocked: dangerous pattern detected/, result.error)
  end

  def test_blocks_drop_table
    result = @stage.call({ text: "DROP TABLE users" })
    refute result.ok?
    assert_match(/Blocked: dangerous pattern detected/, result.error)
  end

  def test_blocks_drop_table_case_insensitive
    result = @stage.call({ text: "drop table sessions" })
    refute result.ok?
    assert_match(/Blocked: dangerous pattern detected/, result.error)
  end

  def test_blocks_format_c
    result = @stage.call({ text: "FORMAT C:" })
    refute result.ok?
    assert_match(/Blocked: dangerous pattern detected/, result.error)
  end

  def test_blocks_format_d
    result = @stage.call({ text: "format D:" })
    refute result.ok?
    assert_match(/Blocked: dangerous pattern detected/, result.error)
  end

  def test_blocks_mkfs
    result = @stage.call({ text: "mkfs.ext4 /dev/sda1" })
    refute result.ok?
    assert_match(/Blocked: dangerous pattern detected/, result.error)
  end

  def test_blocks_dd_if
    result = @stage.call({ text: "dd if=/dev/zero of=/dev/sda" })
    refute result.ok?
    assert_match(/Blocked: dangerous pattern detected/, result.error)
  end

  def test_passes_safe_input
    result = @stage.call({ text: "ls -la /home/user" })
    assert result.ok?
    assert_equal "ls -la /home/user", result.value[:text]
  end

  def test_passes_safe_rm
    result = @stage.call({ text: "rm file.txt" })
    assert result.ok?
    assert_equal "rm file.txt", result.value[:text]
  end

  def test_passes_safe_database_query
    result = @stage.call({ text: "SELECT * FROM users" })
    assert result.ok?
    assert_equal "SELECT * FROM users", result.value[:text]
  end

  def test_passes_empty_text
    result = @stage.call({ text: "" })
    assert result.ok?
  end

  def test_passes_nil_text
    result = @stage.call({})
    assert result.ok?
  end
end
