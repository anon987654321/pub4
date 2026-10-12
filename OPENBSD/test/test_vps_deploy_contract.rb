# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "socket"
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
    degraded = SOURCE[/^DEPLOY_ALL_DEGRADED=\(([^)]*)\)/, 1]&.split
    assert_equal "master", degraded&.last, "when the box cannot take master first, master goes last"
    assert_equal deploy_all.sort, degraded.sort
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
    SOURCE[/^deploy_flag=.*?^trap 'exit 143' TERM$/m]
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
      script = "repo=#{repo}; app=bsdports; deploy_log=#{repo}/deploy.log\nrelease_deploy_lock() { :; }\n#{flag_block}\nhold_deploy_flag\nprint -r -- $deploy_flag\n[[ -e $deploy_flag ]] && print held\n"
      out = IO.popen(["zsh", "-c", script], &:read).lines.map(&:chomp)
      flag = out.first

      assert_equal "held", out.last, "the flag is not on disk while the deploy runs"
      assert File.fnmatch?(guard_glob.sub("/home/dev/pub4", repo), flag, File::FNM_DOTMATCH),
             "#{flag} is not a name resource_guard's #{guard_glob} reads"
      refute File.exist?(flag), "the flag outlived the script, so shedding stays off for 30 minutes"

      rcd_flag = File.read(File.join(ROOT, "OPENBSD", "etc", "rc.d", "bsdports"), encoding: "UTF-8")[%r{touch \S+/(\.deploying\S*)}, 1]
      refute_equal rcd_flag, File.basename(flag),
                   "rc.d removes its own flag after /up, so sharing its name drops the hold mid-deploy"
    end
  end

  def lock_block
    SOURCE[/^lock_dir=.*?^\[\[ -n \$\{VPS_DEPLOY_LOCK_HELD:-\} \]\] \|\| acquire_deploy_lock$/m]
  end

  # Runs the lock block alone in zsh against a scratch directory; returns [output, exit status].
  def lock_run(dir, ttl: 7200, body: "print acquired")
    script = "export VPS_DEPLOY_LOCK_DIR=#{dir}/deploy.lock VPS_DEPLOY_LOCK_TTL=#{ttl}\n#{lock_block}\n#{body}\n"
    out = IO.popen(["zsh", "-c", script, { err: %i[child out] }], &:read)
    [out, $?.exitstatus]
  end

  def test_a_lock_records_its_owner_and_is_released_on_exit
    refute_nil lock_block, "the lock block is gone — the scan broke, or the lock did"
    Dir.mktmpdir do |dir|
      out, status = lock_run(dir, body: "print -r -- $(<$lock_dir/owner)\nrelease_deploy_lock")
      pid, host, epoch = out.lines.last.split

      assert_equal 0, status
      assert_match(/\A\d+\z/, pid)
      assert_equal Socket.gethostname.split(".").first, host
      assert_in_delta Time.now.to_i, epoch.to_i, 30
      refute Dir.exist?(File.join(dir, "deploy.lock")), "release left the lock behind"
    end
  end

  def test_a_lock_whose_pid_is_gone_is_reaped_and_reported
    Dir.mktmpdir do |dir|
      lock = File.join(dir, "deploy.lock")
      Dir.mkdir(lock)
      File.write(File.join(lock, "owner"), "999999 #{Socket.gethostname.split(".").first} #{Time.now.to_i}\n")
      out, status = lock_run(dir)

      assert_equal 0, status
      assert_includes out, "reaping stale lock"
      assert_includes out, "owner pid 999999 is not running"
      assert_includes out, "acquired"
    end
  end

  def test_a_live_local_owner_is_not_reaped_just_because_the_ttl_elapsed
    Dir.mktmpdir do |dir|
      lock = File.join(dir, "deploy.lock")
      Dir.mkdir(lock)
      owner = "#{Process.pid} #{Socket.gethostname.split(".").first} #{Time.now.to_i - 9000}\n"
      File.write(File.join(lock, "owner"), owner)
      out, status = lock_run(dir)

      assert_equal 75, status
      assert_includes out, "another deploy owns"
      assert_equal owner, File.read(File.join(lock, "owner")), "a live owner's stale timestamp must not let a second deploy steal its lock"
    end
  end

  def test_a_live_fresh_lock_refuses_the_second_deploy
    Dir.mktmpdir do |dir|
      lock = File.join(dir, "deploy.lock")
      Dir.mkdir(lock)
      owner = "#{Process.pid} #{Socket.gethostname.split(".").first} #{Time.now.to_i}\n"
      File.write(File.join(lock, "owner"), owner)
      out, status = lock_run(dir)

      assert_equal 75, status
      assert_includes out, "another deploy owns"
      assert_equal owner, File.read(File.join(lock, "owner")), "a live owner's record was disturbed"
    end
  end

  def test_a_bare_fresh_lock_directory_is_left_alone_and_a_stale_one_is_reaped
    Dir.mktmpdir do |dir|
      lock = File.join(dir, "deploy.lock")
      Dir.mkdir(lock)
      _out, status = lock_run(dir)
      assert_equal 75, status

      File.utime(Time.now - 9000, Time.now - 9000, lock)
      out, status = lock_run(dir)
      assert_equal 0, status
      assert_includes out, "no readable owner"
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

      File.read(gemfile, encoding: "UTF-8").scan(%r{path:\s*"\.\./([^/"]+)}).flatten.uniq.each do |sibling|
        synced = sibling == "__shared" || (app == "brgen" && sibling.start_with?("brgen_"))
        assert synced, "#{app}/Gemfile names ../#{sibling}, which vps_ci.sh does not sync beside app/"
      end
    end
  end

  # The trap block alone, in zsh, with doas and write_stamp stubbed: what a failed
  # deploy says, stamps and leaves behind is the contract an operator reads at 3 a.m.
  def finish_block
    SOURCE[/^deploy_stage=start$.*?^trap 'exit 143' TERM$/m]
  end

  def finish_run(dir, body, down: "amber")
    log = File.join(dir, "deploy.log")
    script = <<~ZSH
      app=brgen; repo=#{dir}; deploy_log=#{log}; deploy_flag=#{dir}/.flag; lock_owner=0
      release_deploy_lock() { print released; }
      write_stamp() { stamp_written=1; print "stamp $1 $2"; }
      doas() { [[ $1 == rcctl && $2 == check && $3 == #{down} ]] && return 1; return 0; }
      #{finish_block}
      touch $deploy_flag
      #{body}
    ZSH
    out = IO.popen(["zsh", "-c", script, { err: %i[child out] }], &:read)
    [out, $?.exitstatus, File.exist?(log) ? File.read(log) : ""]
  end

  def test_a_failure_after_the_stop_stamps_failed_names_the_stage_and_what_is_down
    refute_nil finish_block, "the terminal-result block is gone — the scan broke, or the block did"
    Dir.mktmpdir do |dir|
      out, status, log = finish_run(dir, "deploy_stage=migrate; app_stopped=1; exit 1")

      assert_equal 1, status
      assert_includes out, "stamp brgen failed"
      assert_includes out, 'brgen FAILED at stage "migrate" (exit 1)'
      assert_includes out, "brgen was stopped for this deploy and is DOWN"
      assert_includes out, "doas rcctl start brgen"
      assert_includes out, "amber is DOWN"
      refute_includes out, "bsdports is DOWN"
      assert_includes out, "released"
      assert_match(/exit=1 stage=migrate/, log)
      refute File.exist?(File.join(dir, ".flag")), "the deploy flag outlived the script"
    end
  end

  def test_a_failure_before_the_stop_says_the_previous_release_is_still_serving
    Dir.mktmpdir do |dir|
      out, status, = finish_run(dir, "deploy_stage=ci+sync; exit 3", down: "none")

      assert_equal 3, status
      assert_includes out, 'FAILED at stage "ci+sync" (exit 3)'
      assert_includes out, "was not stopped; the previous release is still serving"
      refute_includes out, "is DOWN"
    end
  end

  def test_a_stage_that_already_stamped_is_not_stamped_twice_and_success_is_logged_quietly
    Dir.mktmpdir do |dir|
      out, status, = finish_run(dir, "write_stamp brgen failed; exit 1")
      assert_equal 1, status
      assert_equal 1, out.scan("stamp brgen failed").size

      out, status, log = finish_run(dir, "deploy_stage=final-check; exit 0")
      assert_equal 0, status
      refute_includes out, "FAILED"
      assert_match(/exit=0 stage=final-check/, log)
    end
  end

  def test_a_kill_or_a_dropped_session_is_a_recorded_failure_not_a_silent_end
    Dir.mktmpdir do |dir|
      %w[TERM HUP].each do |signal|
        out, status, log = finish_run(dir, "deploy_stage=precompile; kill -#{signal} $$; sleep 5")
        assert_equal({ "TERM" => 143, "HUP" => 129 }.fetch(signal), status, signal)
        assert_includes out, 'FAILED at stage "precompile"'
        assert_includes log, "stage=precompile"
      end
    end
  end

  # `all` exits from its own loop; a trap installed after that branch never ran for
  # the parent, so every full deploy left its lock to the stale reaper.
  def test_the_terminal_trap_is_installed_before_the_all_branch_can_exit
    assert SOURCE.index("trap finish EXIT") < SOURCE.index("if [[ $app == all ]]; then\n  typeset"),
           "the parent of `vps-deploy all` exits without releasing its lock"
  end

  def disk_block
    SOURCE[/^deploy_stage=preflight-disk$.*?^done$/m]
  end

  def disk_run(dir, free_kb:)
    File.write(File.join(dir, "df"), "#!/bin/sh\nprintf 'Filesystem 1024-blocks Used Available Capacity Mounted on\\n/dev/sd0k 17000000 1000 #{free_kb} 80%% %s\\n' \"$2\"\n")
    File.chmod(0o755, File.join(dir, "df"))
    File.write(File.join(dir, "df"), "#!/bin/sh\nfor last; do :; done\nprintf 'Filesystem 1024-blocks Used Available Capacity Mounted on\\n/dev/x 17000000 1000 #{free_kb} 80%% %s\\n' \"$last\"\n")
    script = "app=brgen; VPS_DEPLOY_DF=#{dir}/df\n#{disk_block}\nprint passed\n"
    out = IO.popen(["zsh", "-c", script, { err: %i[child out] }], &:read)
    [out, $?.exitstatus]
  end

  def test_a_nearly_full_filesystem_refuses_the_deploy_before_anything_is_stopped
    refute_nil disk_block, "the disk preflight is gone - the scan broke, or the check did"
    Dir.mktmpdir do |dir|
      out, status = disk_run(dir, free_kb: 200_000)

      assert_equal 1, status
      assert_includes out, "/home has 195 MB free, the floor is 1024 MB"
      assert_includes out, "Nothing was stopped"
      assert_includes out, "zsh OPENBSD/bin/vps-deploy brgen"
      refute_includes out, "passed"
    end
  end

  def test_enough_free_space_lets_the_deploy_continue
    Dir.mktmpdir do |dir|
      out, status = disk_run(dir, free_kb: 4_000_000)

      assert_equal 0, status, out
      assert_includes out, "passed"
    end
  end
end
