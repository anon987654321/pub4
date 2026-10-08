# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"
require "open3"
require_relative "../lib/operator/ratchet_sponsor"
require_relative "../gates/support/fleet"

class TestRatchetSponsor < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("ratchet-sponsor")
    git("init")
    git("config", "user.email", "test@example.com")
    git("config", "user.name", "test")
    write("MASTER/data/spine.yml", "spine:\n  lib_body_ceiling: 100\npub4_source_ceilings:\n  master: 1\n")
    write("MASTER/lib/a.rb", "A = 1\n")
    git("add", ".")
    git("commit", "-m", "base")
  end

  def teardown
    FileUtils.remove_entry(@dir) if @dir && Dir.exist?(@dir)
  end

  def test_source_file_addition_requires_the_ceiling_file_in_the_same_change
    write("MASTER/lib/b.rb", "B = 1\n")

    error = assert_raises(RuntimeError) do
      Operator::RatchetSponsor.validate!(root: @dir, changed_paths: ["MASTER/lib/b.rb"])
    end
    assert_match(/MASTER\/data\/spine\.yml must change/, error.message)
  end

  def test_source_file_addition_is_sponsored_when_the_ceiling_is_changed
    write("MASTER/lib/b.rb", "B = 1\n")
    write("MASTER/data/spine.yml", "spine:\n  lib_body_ceiling: 101\npub4_source_ceilings:\n  master: 2\n")

    assert Operator::RatchetSponsor.validate!(
      root: @dir,
      changed_paths: ["MASTER/lib/b.rb", "MASTER/data/spine.yml"],
    )
  end

  def test_master_lib_body_growth_requires_the_ceiling_file
    write("MASTER/lib/a.rb", "A = 1\nB = 2\n")

    error = assert_raises(RuntimeError) do
      Operator::RatchetSponsor.validate!(root: @dir, changed_paths: ["MASTER/lib/a.rb"])
    end
    assert_match(/MASTER\/lib body \+1 lines/, error.message)
  end

  def test_rejects_an_irrelevant_spine_edit_as_sponsorship
    write("MASTER/lib/a.rb", "A = 1\nB = 2\n")
    write("MASTER/data/spine.yml", "spine:\n  lib_body_ceiling: 100\npub4_source_ceilings:\n  master: 1\n")

    error = assert_raises(RuntimeError) do
      Operator::RatchetSponsor.validate!(root: @dir, changed_paths: ["MASTER/lib/a.rb", "MASTER/data/spine.yml"])
    end
    assert_match(/ratchet sponsorship required/, error.message)
  end

  def test_new_untracked_master_lib_body_is_priced
    write("MASTER/lib/new.rb", "NEW = 1\n")
    write("MASTER/data/spine.yml", "spine:\n  lib_body_ceiling: 101\npub4_source_ceilings:\n  master: 2\n")

    assert Operator::RatchetSponsor.validate!(
      root: @dir,
      changed_paths: ["MASTER/lib/new.rb", "MASTER/data/spine.yml"],
    )
  end

  def test_fleet_reads_the_canonical_rails_inventory
    assert_equal File.join(Fleet::ROOT, "RAILS", "apps.yml"), Fleet::APPS_YML
    assert_equal %w[amber brgen bsdports], Fleet.app_names
  end

  private

  def write(path, content)
    full = File.join(@dir, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, content)
  end

  def git(*args)
    _out, err, status = Open3.capture3("git", "-C", @dir, *args)
    assert status.success?, err
  end
end
