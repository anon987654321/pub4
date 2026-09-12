# frozen_string_literal: true

require "minitest/autorun"
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
end
