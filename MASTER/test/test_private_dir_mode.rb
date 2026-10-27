# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../lib/boot/paths"
require_relative "../lib/ground/swallow"

# MASTER/.master is tightened by Swallow, Config, WebServer and Trace::Log. On
# vm23 it is dev:master so the master Rails app reaches its config and TTS
# sockets through the group; a plain 0700 took that away and master's /health
# read tts_socket false. Others must still lose access everywhere.
class PrivateDirModeTest < Minitest::Test
  def other_group
    (Process.groups - [Process.egid]).first
  end

  def test_a_directory_in_the_callers_group_is_owner_only
    Dir.mktmpdir do |dir|
      File.chown(nil, Process.egid, dir)
      File.chmod(0o775, dir)

      assert_equal 0o700, MasterPaths.private_dir_mode(dir)
    end
  end

  def test_a_directory_handed_to_another_group_keeps_that_group_and_drops_others
    gid = other_group
    skip "this account belongs to no second group" unless gid

    Dir.mktmpdir do |dir|
      File.chown(nil, gid, dir)
      File.chmod(0o775, dir)

      assert_equal 0o770, MasterPaths.private_dir_mode(dir)
    end
  end

  def test_swallow_leaves_a_shared_state_directory_reachable_by_its_group
    gid = other_group
    skip "this account belongs to no second group" unless gid

    Dir.mktmpdir do |dir|
      state = File.join(dir, ".master")
      Dir.mkdir(state)
      File.chown(nil, gid, state)
      File.chmod(0o770, state)
      Master::Ground::Swallow.send(:private_directory, state)

      assert_equal 0o770, File.stat(state).mode & 0o7777
    end
  end
end
