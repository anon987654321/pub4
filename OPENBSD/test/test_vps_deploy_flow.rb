# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"

# The sequence around the services: the pinned SHA, the preflight, the snapshot,
# the restore and the order. bin/vps-deploy cannot run here (it deploys), so each
# test runs one block of its source in zsh with doas, curl and sleep stubbed and a
# throwaway git remote standing in for github. Nothing reaches vm23.
class VpsDeployFlowTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  SOURCE = File.read(File.join(ROOT, "OPENBSD", "bin", "vps-deploy"), encoding: "UTF-8")
  MASTER_SH = File.read(File.join(ROOT, "OPENBSD", "bin", "vps_deploy_master.sh"), encoding: "UTF-8")
  PIN_BLOCK = SOURCE[/^deploy_refuse\(\).*?^fi$/m]
  FINISH_BLOCK = SOURCE[/^deploy_stage=start$.*?^trap 'exit 143' TERM$/m]
  ORDER_BLOCK = SOURCE[/^DEPLOY_ALL=.*?^choose_deploy_order\(\) \{.*?^\}$/m]

  def zsh(script)
    out, status = Open3.capture2e("zsh", "-c", script)
    [out, status.exitstatus]
  end

  # the pin and the preflight

  # A bare "github", a box checkout one commit behind it, and a stub preflight in the
  # box tree that passes unless the commit under test carries a file named BOOM.
  def with_box
    Dir.mktmpdir do |dir|
      git = ->(*a, chdir: dir) { Open3.capture2e("git", "-c", "user.email=t@t", "-c", "user.name=t", *a, chdir: chdir).first.strip }
      git.call("init", "-q", "--bare", "-b", "main", "origin.git")
      git.call("clone", "-q", "origin.git", "work")
      work = File.join(dir, "work")
      FileUtils.mkdir_p(File.join(work, "OPENBSD/lib"))
      FileUtils.mkdir_p(File.join(work, "MASTER/lib/operator"))
      FileUtils.cp(File.join(ROOT, "OPENBSD/lib/ruby_select.sh"), File.join(work, "OPENBSD/lib/"))
      File.write(File.join(work, "MASTER/lib/operator/canary.rb"),
                 "exit(File.exist?(File.join(File.expand_path('../../..', __dir__), 'BOOM')) ? 1 : 0)\n")
      File.write(File.join(work, "a"), "1")
      git.call("add", "-A", chdir: work)
      git.call("commit", "-qm", "one", chdir: work)
      git.call("push", "-q", "origin", "HEAD:main", chdir: work)
      git.call("clone", "-q", "origin.git", "box")
      yield dir, File.join(dir, "box"), work, git
    end
  end

  def push_commit(work, git, name, body = "x")
    File.write(File.join(work, name), body)
    git.call("add", "-A", chdir: work)
    git.call("commit", "-qm", name, chdir: work)
    git.call("push", "-q", "origin", "HEAD:main", chdir: work)
    git.call("rev-parse", "HEAD", chdir: work)
  end

  def run_pin(box, env = {})
    exports = env.map { |k, v| "export #{k}=#{v}" }.join("\n")
    zsh(<<~ZSH)
      repo=#{box}; lock_owner=1; deploy_stage=start
      doas() { print "amber brgen master sshd"; }
      #{exports}
      #{PIN_BLOCK}
      print "SHA=$VPS_DEPLOY_SHA"; print "STARTED=$VPS_DEPLOY_STARTED"
    ZSH
  end

  def test_the_pin_block_is_present
    refute_nil PIN_BLOCK, "the pin and preflight block is gone, the scan broke, or the block did"
  end

  def test_an_unattested_run_pins_origin_main_runs_the_preflight_and_moves_the_checkout
    with_box do |_dir, box, work, git|
      tip = push_commit(work, git, "two")
      out, status = run_pin(box)
      assert_equal 0, status, out
      assert_includes out, "SHA=#{tip}"
      assert_includes out, "preflight on #{tip}"
      assert_equal tip, git.call("rev-parse", "HEAD", chdir: box)
      assert_equal "main", git.call("rev-parse", "--abbrev-ref", "HEAD", chdir: box)
      assert_includes out, "STARTED=amber brgen master sshd", "the started services are recorded before anything is touched"
    end
  end

  def test_a_failing_preflight_refuses_and_leaves_the_checkout_on_the_old_commit
    with_box do |_dir, box, work, git|
      before = git.call("rev-parse", "HEAD", chdir: box)
      push_commit(work, git, "BOOM")
      out, status = run_pin(box)
      assert_equal 1, status
      assert_includes out, "preflight failed"
      assert_includes out, "Nothing was stopped"
      assert_equal before, git.call("rev-parse", "HEAD", chdir: box), "the checkout moved onto a commit that does not boot"
      assert_equal "main", git.call("rev-parse", "--abbrev-ref", "HEAD", chdir: box)
    end
  end

  def test_an_attested_preflight_must_name_the_sha_that_will_deploy
    with_box do |_dir, box, work, git|
      tip = push_commit(work, git, "two")
      out, status = run_pin(box, VPS_DEPLOY_PREFLIGHT_SHA: "0" * 40)
      assert_equal 1, status
      assert_includes out, "preflight ran on #{'0' * 40} but this run would deploy #{tip}"
      out, status = run_pin(box, VPS_DEPLOY_PREFLIGHT_SHA: tip)
      assert_equal 0, status, out
      assert_includes out, "preflight passed on the operator's machine"
      refute_includes out, "preflight on #{tip} (syntax"
    end
  end

  def test_an_explicit_sha_is_deployed_not_whatever_main_is_by_then
    with_box do |_dir, box, work, git|
      middle = push_commit(work, git, "two")
      push_commit(work, git, "three")
      out, status = run_pin(box, VPS_DEPLOY_SHA: middle, VPS_DEPLOY_PREFLIGHT_SHA: middle)
      assert_equal 0, status, out
      assert_equal middle, git.call("rev-parse", "HEAD", chdir: box)
    end
  end

  def test_the_break_glass_skip_needs_the_human_acknowledgement
    with_box do |_dir, box, work, git|
      push_commit(work, git, "BOOM")
      out, status = run_pin(box, VPS_DEPLOY_SKIP_PREFLIGHT: "1")
      assert_equal 1, status
      assert_includes out, "needs the human-only I_UNDERSTAND_FAST_DEPLOY=1"
      out, status = run_pin(box, VPS_DEPLOY_SKIP_PREFLIGHT: "1", I_UNDERSTAND_FAST_DEPLOY: "1")
      assert_equal 0, status, out
      assert_includes out, "preflight skipped (break-glass)"
    end
  end

  def test_a_sha_that_is_not_a_fast_forward_is_refused
    with_box do |_dir, box, work, git|
      first = git.call("rev-parse", "HEAD", chdir: work)
      push_commit(work, git, "two")
      git.call("pull", "-q", chdir: box)
      out, status = run_pin(box, VPS_DEPLOY_SHA: first, VPS_DEPLOY_PREFLIGHT_SHA: first)
      assert_equal 1, status
      assert_includes out, "not a fast-forward"
    end
  end

  def test_later_steps_check_the_pin_and_never_pull
    refute_match(/git -C "\$repo" pull/, SOURCE)
    assert_match(/rev-parse HEAD\) == "\$VPS_DEPLOY_SHA"/, SOURCE)
    assert_includes MASTER_SH, '[ "$(git rev-parse HEAD)" = "$VPS_DEPLOY_SHA" ]'
    assert_operator SOURCE.index("deploy_refuse()"), :<, SOURCE.index("DEPLOY_ALL=("), "the pin comes before any deploy"
  end

  # the restore

  # State lives in files: <dir>/up/<svc> exists when the service runs. `restart`
  # appends to <dir>/log and brings the service up after <delay> /up polls.
  def restore_run(dir, down:, started: "amber brgen bsdports master sshd", body: "exit 1", never: [], shed: nil)
    FileUtils.mkdir_p(File.join(dir, "up"))
    started.split.each { |svc| FileUtils.touch(File.join(dir, "up", svc)) unless down.include?(svc) }
    File.write(File.join(dir, "shed"), "#{shed}\n") if shed
    script = <<~ZSH
      app=all; repo=#{dir}; deploy_log=#{dir}/deploy.log; deploy_flag=#{dir}/.flag; lock_owner=1
      export VPS_DEPLOY_STARTED="#{started}" VPS_DEPLOY_POLL=1 VPS_DEPLOY_RESTORE_WAIT=3 VPS_DEPLOY_SHED_FILE=#{dir}/shed
      release_deploy_lock() { print released; }
      sleep() { :; }
      doas() {
        [[ $1 == rcctl ]] || return 0
        case $2 in
          check) [[ -e #{dir}/up/$3 ]] ;;
          restart)
            print "restart $3" >> #{dir}/log
            [[ " #{never.join(' ')} " == *" $3 "* ]] && return 0
            # a ported service answers /up only on its second poll, like a booting Falcon
            if [[ -n ${deploy_ports[$3]:-} ]]; then touch #{dir}/pend_$3; else touch #{dir}/up/$3; fi
            return 0 ;;
        esac
      }
      curl() {
        local port=${${@[-1]##*:}%%/*} s
        for s in amber brgen bsdports master; do
          [[ $deploy_ports[$s] == $port ]] || continue
          [[ -e #{dir}/up/$s ]] && return 0
          [[ -e #{dir}/pend_$s ]] || return 1
          [[ -e #{dir}/polled_$s ]] || { touch #{dir}/polled_$s; return 1 }
          touch #{dir}/up/$s; print "up $s" >> #{dir}/log; return 0
        done
        return 1
      }
      typeset -A deploy_ports; deploy_ports=(master 41004 brgen 41001 amber 41002 bsdports 41003)
      load_deploy_ports() { return 0 }
      #{FINISH_BLOCK}
      #{body}
    ZSH
    out, status = zsh(script)
    [out, status, File.exist?(File.join(dir, "log")) ? File.read(File.join(dir, "log")).lines.map(&:strip) : []]
  end

  def test_a_halted_pass_restores_every_missing_service_one_at_a_time_in_serving_order
    Dir.mktmpdir do |dir|
      out, status, log = restore_run(dir, down: %w[master amber bsdports], body: "deploy_stage=all:master; halted_app=master; exit 1")
      assert_equal 1, status, "the failing exit status must survive the restore"
      assert_equal ["restart amber", "up amber", "restart bsdports", "up bsdports", "restart master", "up master"], log,
                   "serving order; each answers /up before the next is started; brgen was up"
      assert_includes out, "restore amber ok"
      assert_includes out, "restore master (stopped by this deploy)"
      assert_includes out, "all FAILED at stage \"all:master\""
      assert_includes out, "released"
      refute_includes out, "STILL DOWN"
    end
  end

  def test_a_service_that_never_answers_is_reported_and_does_not_stop_the_others
    Dir.mktmpdir do |dir|
      out, status, log = restore_run(dir, down: %w[brgen amber], never: %w[brgen])
      assert_equal 1, status
      assert_includes out, "restore brgen FAILED"
      assert_includes out, "STILL DOWN after restore: brgen"
      assert_includes out, "restore amber ok"
      assert_equal 2, log.count("restart brgen"), "one retry, then it is given up on"
      assert_includes log, "up amber"
      assert_includes out, "production is NOT fully restored"
    end
  end

  def test_shed_services_are_counted_apart_from_the_deploys_own_stops
    Dir.mktmpdir do |dir|
      out, = restore_run(dir, down: %w[amber bsdports brgen], shed: "bsdports", body: "own_stops+=(brgen); exit 1")
      assert_includes out, "restore brgen (stopped by this deploy)"
      assert_includes out, "restore bsdports (shed by resource_guard)"
      assert_includes out, "restore amber (down for another reason"
    end
  end

  def test_nothing_is_restored_when_everything_that_was_started_is_still_up
    Dir.mktmpdir do |dir|
      out, status, log = restore_run(dir, down: [])
      assert_equal 1, status
      assert_empty log
      refute_includes out, "restore "
    end
  end

  def test_a_clean_exit_restores_nothing_and_a_child_never_restores
    Dir.mktmpdir do |dir|
      _out, status, log = restore_run(dir, down: %w[amber], body: "exit 0")
      assert_equal 0, status
      assert_empty log
      _out, status, log = restore_run(dir, down: %w[amber], body: "lock_owner=0; exit 1")
      assert_equal 1, status
      assert_empty log, "only the process that owns the lock restores"
    end
  end

  def test_the_lock_is_released_whichever_way_the_run_ends
    Dir.mktmpdir do |dir|
      %w[exit\ 1 kill\ -TERM\ $$;\ sleep\ 5].each do |body|
        out, = restore_run(dir, down: [], body: body)
        assert_includes out, "released", body
      end
    end
  end

  # the order

  def order_run(dir, avail:, apps_up: true, started: "brgen amber bsdports master")
    File.write(File.join(dir, "guard.log"), "2026-10-12T06:30:02Z load=1.0 mem_avail=#{avail}% shed=0 deploy=0\n") if avail
    zsh(<<~ZSH)
      repo=#{dir}; RUBY=#{RbConfig.ruby}; VPS_DEPLOY_GUARD_LOG=#{dir}/guard.log; VPS_DEPLOY_STARTED="#{started}"
      VPS_DEPLOY_POLL=1
      typeset -A deploy_ports; deploy_ports=(master 41004 brgen 41001 amber 41002 bsdports 41003)
      load_deploy_ports() { return 0 }
      wait_up() { #{apps_up ? 'return 0' : 'return 1'} }
      typeset -a deploy_order
      #{ORDER_BLOCK}
      choose_deploy_order
      print "ORDER=${deploy_order}"
    ZSH
  end

  def test_master_leads_only_when_every_app_is_up_and_memory_allows
    Dir.mktmpdir do |dir|
      out, = order_run(dir, avail: 14)
      assert_includes out, "ORDER=master brgen amber bsdports"

      out, = order_run(dir, avail: 8)
      assert_includes out, "ORDER=brgen amber bsdports master"
      assert_includes out, "memory availability 8% is under 10%"

      out, = order_run(dir, avail: 14, apps_up: false)
      assert_includes out, "ORDER=brgen amber bsdports master"
      assert_includes out, "is not answering /up"
    end
  end

  def test_unreadable_memory_is_not_a_licence_to_put_master_first
    Dir.mktmpdir do |dir|
      out, = order_run(dir, avail: nil)
      assert_includes out, "ORDER=brgen amber bsdports master"
      assert_includes out, "unreadable"
    end
  end

  # the rest of the sequence

  def test_memory_heavy_steps_wait_for_booting_apps_and_flows_run_per_app
    assert_operator SOURCE.index("settle_boots\n  jobs_service"), :<, SOURCE.index("OPENBSD/bin/vps_ci.sh")
    assert_operator SOURCE.index("(assets precompile)\"\nsettle_boots"), :<, SOURCE.index("rails_assets_precompile_as_app")
    assert_includes SOURCE, 'FLOW_APP="$app" MASTER_STRICT=deploy GATE_AUTOFIX=0 "$RUBY"'
    assert_includes SOURCE, "FLOW_APP=master MASTER_STRICT=deploy"
  end

  def test_settle_boots_waits_only_for_running_services
    Dir.mktmpdir do |dir|
      out, status = zsh(<<~ZSH)
        repo=#{dir}; export VPS_DEPLOY_STARTED="brgen amber sshd"
        typeset -A deploy_ports; deploy_ports=(brgen 41001 amber 41002)
        load_deploy_ports() { return 0 }
        doas() { [[ $3 == brgen ]] }
        wait_up() { print "waited $1 $2"; return 0 }
        #{SOURCE[/^settle_boots\(\) \{.*?^\}$/m]}
        settle_boots
      ZSH
      assert_equal 0, status
      assert_includes out, "waited 41001"
      refute_includes out, "waited 41002", "a service that is down is not booting"
    end
  end
end
