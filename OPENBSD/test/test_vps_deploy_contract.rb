# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "yaml"

# vps-deploy is the entrypoint for every production deploy and had no test.
#
# Running it is not an option — it deploys — so this reads the source for the
# three things it promises that a reader cannot otherwise check: that the fleet
# it deploys is the fleet apps.yml declares, that the order which makes the pass
# survive its own side effects is still that order, and that it refuses to run as
# root rather than dying at `git pull` with a message about host keys.
class VpsDeployContractTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  SOURCE = File.read(File.join(ROOT, "OPENBSD", "bin", "vps-deploy"), encoding: "UTF-8")
  APPS = YAML.safe_load_file(File.join(ROOT, "RAILS", "apps.yml")).fetch("apps").keys.map(&:to_s)
  MASTER_DEPLOY = File.read(File.join(ROOT, "OPENBSD", "bin", "vps_deploy_master.sh"), encoding: "UTF-8")

  def deploy_all
    SOURCE[/^DEPLOY_ALL=\(([^)]*)\)/, 1]&.split
  end

  def test_the_fleet_it_deploys_is_the_fleet_apps_yml_declares
    refute_nil deploy_all, "DEPLOY_ALL not found — the scan broke, not the script"

    # master is not in apps.yml: it is not a Rails app under /home/*/app, which is
    # the reason an operator enumerating the apps leaves it behind and the reason
    # it is named here at all.
    assert_equal APPS.sort, (deploy_all - ["master"]).sort
    assert_includes deploy_all, "master"
  end

  # The script's own comment carries the argument: master leads because it is
  # independent of the Rails apps and is the one that gets forgotten; amber and
  # bsdports go last because every deploy sheds them, so deploying them last folds
  # the restore into the same pass instead of leaving a window with nobody looking.
  def test_the_order_that_survives_its_own_side_effects
    assert_equal "master", deploy_all.first
    assert_equal %w[amber bsdports], deploy_all.last(2).sort
  end

  def test_deploy_paths_export_openbsd_package_path
    expected = "export PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin"
    assert_includes SOURCE, expected
    assert_includes MASTER_DEPLOY, expected
  end

  def test_it_rejects_an_unknown_deploy_target
    assert_match(
      /case \$app in\n\s+all\|master\|brgen\|amber\|bsdports\) ;;.*\n\s+\*\) .*exit 2/,
      SOURCE,
      "an arbitrary app name must not reach filesystem, service or deploy-stamp paths"
    )
  end

  def test_it_refuses_to_run_as_root
    assert_match(/if \[\[ \$\(id -u\) -eq 0 \]\]; then/, SOURCE,
                 "the uid guard is gone — root reaches git pull and fails on a host key instead")
    guard = SOURCE[/if \[\[ \$\(id -u\) -eq 0 \]\]; then.*?^fi$/m]

    assert_match(/exit 2/, guard, "the root guard must exit, not warn")
  end

  # SKIP_CI=1 does not mean no gate runs: it takes the ${app}.sh branch, which
  # reaches rails_runtime_gate through deploy_tracked_app. The name says otherwise,
  # and a hotfix pushed on that belief is how something bin/ci would have caught
  # gets onto the box. The branch must keep running the app script.
  def test_skip_ci_takes_the_narrower_gate_rather_than_no_gate
    branch = SOURCE[/if \[\[ \$\{SKIP_CI:-\} == 1 \]\]; then(.*?)^else$/m]

    refute_nil branch, "the SKIP_CI branch is gone — the scan broke, or the path did"
    assert_match(%r{RAILS/\$\{app\}/\$\{app\}\.sh}, branch,
                 "SKIP_CI=1 must still run the app script, which is what reaches rails_runtime_gate")
  end

  GUARD = File.read(File.join(ROOT, "OPENBSD", "bin", "resource_guard.sh"), encoding: "UTF-8")

  def flag_block
    SOURCE[/^deploy_flag=.*?^hold_deploy_flag$/m]
  end

  # resource_guard stops shedding while a .deploying* flag is fresh. rc.d holds
  # one only across the restart, so CI and the gates ran as strikes and the app
  # deployed last was shed on the first tick after its flag came off. The flag
  # this script holds has to be one the guard reads, live across the deploy,
  # and gone when the script exits.
  def test_the_deploy_flag_is_held_for_the_whole_deploy_and_released_on_exit
    refute_nil flag_block, "the deploy flag block is gone — the scan broke, or the flag did"
    guard_glob = GUARD[%r{for _flag in (/home/dev/pub4/\.deploying\S*); do}, 1]
    refute_nil guard_glob, "resource_guard no longer reads a deploy flag glob"

    Dir.mktmpdir do |repo|
      script = "repo=#{repo}; app=bsdports\n#{flag_block}\nprint -r -- $deploy_flag\n[[ -e $deploy_flag ]] && print held\n"
      out = IO.popen(["zsh", "-c", script], &:read).lines.map(&:chomp)
      flag = out.first

      assert_equal "held", out.last, "the flag is not on disk while the deploy runs"
      assert File.fnmatch?(guard_glob.sub("/home/dev/pub4", repo), flag, File::FNM_DOTMATCH),
             "#{flag} is not a name resource_guard's #{guard_glob} reads"
      refute File.exist?(flag), "the flag outlived the script, so shedding stays off for 30 minutes"

      rcd_flag = File.read(File.join(ROOT, "OPENBSD", "etc", "rc.d", "bsdports"))[%r{touch \S+/(\.deploying\S*)}, 1]
      refute_equal rcd_flag, File.basename(flag),
                   "rc.d removes its own flag after /up, so sharing its name drops the hold mid-deploy"
    end
  end

  def test_the_flag_is_taken_before_ci_and_the_app_is_checked_before_ok
    assert_operator SOURCE.index("\nhold_deploy_flag\n"), :<, SOURCE.index("OPENBSD/bin/vps_ci.sh")
    assert_operator SOURCE.rindex(%(doas rcctl check "$app")), :>, SOURCE.index(%(GATE_AUTOFIX=0 "$RUBY" "$repo/MASTER/gates/runner.rb"))
  end

  # The copy-tree on vm23 keeps path gems beside app/, so every ../X an app
  # Gemfile names must be a directory vps_ci.sh syncs there. The layout moved
  # (shared became __shared, engines/ became sibling brgen_* directories) and the
  # CI mirror kept building the old one until a deploy died on
  # "The path /home/brgen/__shared does not exist".
  def test_ci_mirror_syncs_every_sibling_path_gem_the_gemfiles_name
    ci = File.read(File.join(ROOT, "OPENBSD", "bin", "vps_ci.sh"), encoding: "UTF-8")
    assert_includes ci, "shared_dir=/home/${app}/__shared"
    assert_includes ci, "RAILS/brgen_*"
    # The suite outlasts the guard's one-hour default on this box.
    assert_includes ci, "export PUB4_CI_TIMEOUT=${PUB4_CI_TIMEOUT:-7200}"
    # A directory the repo no longer has must not survive the sync, or its stale tests keep running.
    assert_includes ci, '[[ -d $src/engines ]] || doas rm -rf "${app_dir}/engines"'

    APPS.each do |app|
      gemfile = File.join(ROOT, "RAILS", app, "Gemfile")
      next unless File.file?(gemfile)

      File.read(gemfile).scan(%r{path:\s*"\.\./([^/"]+)}).flatten.uniq.each do |sibling|
        synced = sibling == "__shared" || (app == "brgen" && sibling.start_with?("brgen_"))
        assert synced, "#{app}/Gemfile names ../#{sibling}, which vps_ci.sh does not sync beside app/"
      end
    end
  end
end
