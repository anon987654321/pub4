# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"

# MASTER's TTS worker has to find the bundle the deploy installed.
#
# vps_deploy_master.sh installs MASTER/Gemfile as the deploy user into
# /home/dev/.bundle/master and records that path in MASTER/.bundle/config. The
# worker runs as the `master` user (and as dev for the rc.d warm-up) and used
# to look only in its own ~/.master/bundler store, which no deploy fills, so it
# tried a full `bundle install` inside a 15s probe and /health said
# "worker selftest exited : deps0: installing bundle for MASTER" (2026-10-12).
# Text and a temp directory, never the box: these hold the two ends of that
# hand-off to the same spelling.
class MasterTtsBundleContractTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  DEPLOY = File.read(File.join(ROOT, "OPENBSD/bin/vps_deploy_master.sh"))
  RC_D = File.read(File.join(ROOT, "OPENBSD/etc/rc.d/master"))
  MANAGER = File.read(File.join(ROOT, "MASTER/lib/boot/dependency_manager.rb"))

  def test_the_deploy_records_the_bundle_path_in_masters_own_bundle_config
    assert_match(/bundle_config_once "\$ROOT\/MASTER" PATH "\$BUNDLE_PATH_DEV"/, DEPLOY)
    assert_match(/^BUNDLE_PATH_DEV=\/home\/dev\/\.bundle\/master$/, DEPLOY)
  end

  def test_the_dependency_manager_reads_that_same_config_key
    assert_includes MANAGER, 'File.join(@root, ".bundle", "config")'
    assert_includes MANAGER, "BUNDLE_PATH:"
    assert_includes MANAGER, "def adopt_deploy_bundle"
  end

  def test_the_deploy_bundle_is_read_frozen_and_never_installed_by_the_reader
    body = MANAGER[/def deploy_bundle_env.*?^      end/m]
    refute_nil body
    assert_includes body, '"BUNDLE_FROZEN" => "true"'
    assert_includes body, "development:test", "the deploy installs without these groups, so the check must too"
  end

  def test_the_rc_d_warm_up_runs_as_dev_with_devs_home
    warm = RC_D[/if su -m dev -c '.*?'/m]
    refute_nil warm, "rc.d master must warm TTS as dev"
    assert_includes warm, "export HOME=/home/dev;", "su -m keeps root's HOME, and /root/.master is not writable"
  end

  def test_the_smoke_polls_and_prints_the_reason_instead_of_one_unexplained_abort
    assert_includes DEPLOY, '"blocked"'
    assert_match(/while \[ "\$_try" -lt \d+ \]/, DEPLOY)
  end

  def test_the_dependency_manager_resolves_the_path_the_deploy_writes
    Dir.mktmpdir("deploy-bundle-contract-") do |tmp|
      gems = File.join(tmp, "gems")
      FileUtils.mkdir_p([gems, File.join(tmp, "app", ".bundle")])
      File.write(File.join(tmp, "app", ".bundle", "config"), %(---\nBUNDLE_DISABLE_CHECKSUM_VALIDATION: "true"\nBUNDLE_PATH: "#{gems}"\n))
      File.write(File.join(tmp, "app", "Gemfile"), "source \"https://rubygems.org\"\n")
      require File.join(ROOT, "MASTER/lib/boot/dependency_manager")
      manager = Master::Boot::DependencyManager.new(root: File.join(tmp, "app"), env: {}, out: StringIO.new, home: tmp)

      assert_equal gems, manager.send(:deploy_bundle_path)
    end
  end
end
