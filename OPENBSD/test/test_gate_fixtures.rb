# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
require_relative "../lib/utf8"
require_relative "../installed_targets_gate"

# Every OPENBSD gate beside the defect it exists to catch.
#
# A gate that only ever runs over this checkout and says clean proves nothing: it
# says clean just as well with its body gutted. So each pair here plants the
# shape the gate must flag, watches it fail, and runs the committed tree for the
# shape it must not — the house decision of 2026-08-22.
class InstalledTargetsGateFixtureTest < Minitest::Test
  GATE = Deploy::InstalledTargetsGate

  def setup
    @tmp = Dir.mktmpdir("installed-targets")
    GATE.root = @tmp
  end

  def teardown
    GATE.root = GATE::DEFAULT_ROOT
    FileUtils.remove_entry(@tmp)
  end

  def plant(rel, body)
    path = File.join(@tmp, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
  end

  def missing = GATE.orphans.keys

  # The daily.local shape the gate was written for: a guard on a target nothing
  # installs.
  def test_a_cron_target_nothing_installs_is_named
    plant("etc/crontab.vm23", "*/5 * * * * /usr/local/bin/ghost.sh\n")

    assert_equal ["bin/ghost.sh"], missing
  end

  # resource_guard.sh is installed from the tree root and calls its crisis tier by
  # its installed path. A script the repo installs is a referrer like any crontab.
  def test_an_installed_script_naming_a_target_nothing_installs_is_named
    plant("OPERATOR.sh", %(install -m 755 "${SCRIPT_DIR}/guard.sh" /usr/local/bin/guard.sh\n))
    plant("guard.sh", "[ -x /usr/local/bin/crisis.sh ] && /usr/local/bin/crisis.sh\n")

    assert_equal ["bin/crisis.sh"], missing
  end

  def test_an_install_line_provides_its_target
    plant("OPERATOR.sh", <<~SH)
      install -m 755 "${SCRIPT_DIR}/guard.sh" /usr/local/bin/guard.sh
      install -m 755 "${SCRIPT_DIR}/crisis.sh" /usr/local/bin/crisis.sh
    SH
    plant("guard.sh", "/usr/local/bin/crisis.sh\n")
    plant("crisis.sh", "#!/bin/ksh\n")

    assert_empty missing
  end

  # libexec is copied wholesale like bin, and root dot-sources what is in it.
  def test_a_libexec_target_is_measured_and_shipping_it_provides_it
    plant("etc/daily.local", ". /usr/local/libexec/helper.ksh\n")

    assert_equal ["libexec/helper.ksh"], missing

    plant("usr/local/libexec/helper.ksh", "#!/bin/ksh\n")

    assert_empty missing
  end

  def test_a_directory_named_in_prose_is_not_a_target
    plant("etc/daily.local", "# nothing lives in /usr/local/bin/lib/ any more\n")

    assert_empty GATE.referenced
  end

  def test_the_committed_tree_names_the_crisis_tier_and_provides_it
    GATE.root = GATE::DEFAULT_ROOT

    assert_includes GATE.referenced.keys, "bin/emergency_cpu.sh",
                    "resource_guard.sh's crisis path is no longer read, so a missing install would pass"
    assert_includes GATE.referenced.keys, "libexec/stale_ci_cleanup.ksh"
    assert_empty GATE.orphans
  end
end

# OPERATOR.sh re-runs on a live box, so each destructive step has to be one a
# second run survives. The check reads the script for four guarantees; these
# hand it the script with one of them broken.
class IdempotencyFixtureTest < Minitest::Test
  OPENBSD = File.expand_path("..", __dir__)
  CHECK = File.join(OPENBSD, "verify_openbsd_idempotency.rb")
  BACKUP = "backup_directory /var/nsd/zones/master nsd-zones\n"
  DELETE = "rm -rf /var/nsd/etc/*(/) /var/nsd/zones/master/*(/)\n" # scan: intentional — fixture text, never run
  REST = <<~SH
    cp -R "${src}/home" "/var/backups/home"
    bin/rails db:prepare
    rcctl restart ${svc} || rcctl start ${svc}
  SH

  def verdict(body)
    Dir.mktmpdir("idempotency") do |dir|
      path = File.join(dir, "OPERATOR.sh")
      File.write(path, body)
      out, status = Open3.capture2e(RbConfig.ruby, CHECK, path)
      [status.success?, out]
    end
  end

  def test_the_zones_deleted_with_no_backup_is_refused
    ok, out = verdict(DELETE + REST)

    refute ok, "a zone wipe with no backup passed"
    assert_includes out, "nsd backup does not precede destructive delete"
  end

  def test_a_backup_taken_after_the_delete_is_refused
    ok, = verdict(DELETE + BACKUP + REST)

    refute ok, "a backup of zones already deleted passed"
  end

  def test_a_restart_with_no_start_fallback_is_refused
    ok, out = verdict(BACKUP + DELETE + REST.sub(" || rcctl start ${svc}", ""))

    refute ok
    assert_includes out, "missing restart/start fallback"
  end

  def test_the_snippet_with_every_guarantee_passes
    ok, out = verdict(BACKUP + DELETE + REST)

    assert ok, out
  end

  def test_the_committed_operator_script_passes
    out, status = Open3.capture2e(RbConfig.ruby, CHECK)

    assert status.success?, out
  end
end

# Every app deploy calls into RAILS/_deploy.sh. The identity check used to find
# the function by its spelling, which a comment satisfies as well as a definition.
class DeployIdentityFixtureTest < Minitest::Test
  OPENBSD = File.expand_path("..", __dir__)
  load File.join(OPENBSD, "verify_deploy_identity.rb")

  def missing(body)
    Dir.mktmpdir("identity") do |dir|
      File.write(File.join(dir, "helper.sh"), "need_cmd() { :; }\n")
      library = File.join(dir, "_deploy.sh")
      File.write(library, body)
      shell_functions_missing(library, %w[deploy_tracked_app need_cmd])
    end
  end

  def test_a_function_named_only_in_a_comment_is_missing
    assert_equal %w[deploy_tracked_app need_cmd], missing("# deploy_tracked_app() lives here\n")
  end

  def test_a_function_from_a_sourced_file_counts
    body = %(. "${${(%):-%x}:A:h}/helper.sh"\ndeploy_tracked_app() { :; }\n)

    assert_empty missing(body)
  end

  def test_the_committed_library_defines_every_shared_function
    assert_empty shell_functions_missing(File.join(OPENBSD, "..", "RAILS", "_deploy.sh"), SHARED_FUNCTIONS)
  end

  def test_the_run_fails_on_a_library_that_defines_nothing
    Dir.mktmpdir("identity") do |dir|
      library = File.join(dir, "_deploy.sh")
      File.write(library, "# deploy_tracked_app() lives here\n")
      out, status = Open3.capture2e(RbConfig.ruby, File.join(OPENBSD, "verify_deploy_identity.rb"), library)

      refute status.success?
      assert_includes out, "defines no deploy_tracked_app"
    end
  end

  def test_the_committed_tree_passes
    out, status = Open3.capture2e(RbConfig.ruby, File.join(OPENBSD, "verify_deploy_identity.rb"))

    assert status.success?, out
  end
end

require_relative "../gates/port_inventory"

# port_inventory handed the fleet with one port moved, so each mirror it reads
# must notice apps.yml and its copy no longer agree.
class PortInventoryFixtureTest < Minitest::Test
  GATE = Deploy::PortInventoryGate

  def apps = @apps ||= Deploy::Inventory.new(root: GATE::ROOT).apps

  # The fleet as apps.yml would describe it after brgen moved to port 40000.
  def moved = apps.map { |app| app.name == "brgen" ? app.dup.tap { |a| a.port = 40_000 } : app }

  def findings(check, fleet, *rest)
    result = Deploy::GateResult.new
    GATE.new.send(check, result, fleet, *rest)
    result.failures
  end

  def test_relayd_forwarding_to_the_old_port_fails
    old = apps.find { |app| app.name == "brgen" }.port

    assert_includes findings(:check_relayd_ports, moved),
                    "brgen: relayd.conf forwards to port #{old}, apps.yml says 40000"
  end

  def test_a_smoke_probe_on_the_old_port_fails
    assert_match(/probes port \d{5}, which no app in apps.yml listens on \(line names brgen\)/,
                 findings(:check_smoke_probes, moved).join(" | "))
  end

  # A probe that names one app and another app's port warms the wrong process,
  # and the bare `smoke <app> <port>` form is read as well as the URL form.
  def test_a_probe_naming_one_app_on_another_apps_port_fails
    named, other = apps.first(2)
    Dir.mktmpdir("smoke") do |dir|
      File.write(File.join(dir, "smoke.sh"), <<~SH)
        smoke #{named.name} #{other.port}
        curl -fsS http://127.0.0.1:#{named.port}/up
      SH
      result = Deploy::GateResult.new
      GATE.new.send(:check_smoke_probes, result, apps, root: dir, scripts: ["smoke.sh"])

      assert_equal ["smoke.sh:1 probes port #{other.port}, which no app in apps.yml listens on (line names #{named.name})"],
                   result.failures
    end
  end

  def test_operator_app_ports_on_the_old_port_fails
    assert_includes findings(:check_openbsd_ports, moved).join(" | "), "brgen: OpenBSD APP_PORTS"
  end

  def test_two_apps_on_one_port_fail
    clash = apps.first(2).map(&:dup).each { |app| app.port = 40_000 }

    assert_equal ["port collision 40000: #{clash.map(&:name).join(', ')}"], findings(:check_uniques, clash, :port)
  end

  def test_the_committed_tree_passes
    result = GATE.run

    assert_equal :passed, result.outcome, result.failures.join("\n")
    assert_operator apps.size, :>=, 3
  end
end

# shell_syntax_gate parses each script with the interpreter its shebang names.
class ShellSyntaxFixtureTest < Minitest::Test
  GATE = File.expand_path("../shell_syntax_gate.rb", __dir__)

  def scan(files)
    Dir.mktmpdir("shell-syntax") do |root|
      files.each do |rel, body|
        path = File.join(root, "OPENBSD", rel)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, body)
      end
      out, status = Open3.capture2e({ "SHELL_SYNTAX_ROOT" => root }, RbConfig.ruby, GATE)
      [status.success?, out]
    end
  end

  def test_a_script_that_does_not_parse_fails_and_is_named
    ok, out = scan("bin/broken" => "#!/usr/bin/env zsh\nif [[ -n x ]]; then\n  print hi\n",
                   "fine.sh" => "#!/bin/sh\necho ok\n")

    refute ok
    assert_includes out, "1 of 2 scripts do not parse"
    assert_includes out, "zsh -n OPENBSD/bin/broken"
  end

  # The shebang picks the parser: `set -A` is ksh and a syntax error to nothing
  # else that matters here, so a ksh script must not be read by sh.
  def test_each_script_is_parsed_by_its_own_shebang
    ok, out = scan("usr/local/bin/warm.sh" => "#!/bin/ksh\nset -A T a b\nfor t in \"${T[@]}\"; do print $t; done\n")

    assert ok, out
    assert_includes out, "1 scripts parse"
  end

  def test_a_tree_with_no_shebangs_is_a_broken_scan
    ok, out = scan("notes.sh" => "echo no shebang\n")

    refute ok
    assert_includes out, "the scan is broken"
  end

  def test_the_committed_tree_parses
    out, status = Open3.capture2e(RbConfig.ruby, GATE)

    assert status.success?, out
  end
end

class DeploySmokeFixtureTest < Minitest::Test
  OPENBSD = File.expand_path("..", __dir__)
  require File.join(OPENBSD, "deploy_smoke_gate.rb")

  PUBLIC = %w[/up /health].freeze

  def rc_findings(body)
    failures = []
    check_master_rc(failures, body, PUBLIC)
    failures
  end

  def test_a_warmup_that_needs_a_token_is_refused
    body = %(curl -fsS "http://127.0.0.1:${PORT}/chat/metrics?token=${TOKEN}"\n)
    named = rc_findings(body).join(" | ")

    assert_includes named, "carries a credential"
    assert_includes named, "needs auth since the tier gate"
    assert_includes named, "no warmup request asks a path AuthTier serves without a token"
  end

  def test_a_start_block_with_nothing_to_warm_is_refused
    assert_includes rc_findings("rcctl restart relayd\n"), "rc.d/master: no warmup request to the local port"
  end

  # The query string is the script's own business, which the old check was not:
  # it wanted `chat/message?message=ping` spelled exactly.
  def test_any_credential_free_warmup_through_a_public_path_passes
    body = %(curl -fsS "http://127.0.0.1:${PORT}/up"\ncurl -fsS "http://127.0.0.1:${PORT}/chat/message?message=hello"\n)

    assert_empty rc_findings(body)
  end

  # The line rc.d/master carried: a restart printed the operator token into
  # ~/vps-deploy.log. Placeholders only; no real token belongs in a test.
  def test_a_script_that_prints_a_token_value_is_refused
    ruby = %q(puts t ? "web: #{u}/?token=#{t}" : "web: #{u}") + "\n"
    shell = %(print "web: ${url}/?token=${WEB_TOKEN}"\nlogger -t master "open $url?token=$tok"\n)

    assert_equal ["rc.d/master:1"], TokenEcho.echoes(ruby, "rc.d/master")
    assert_equal ["bin/x:1", "bin/x:2"], TokenEcho.echoes(shell, "bin/x")
  end

  def test_a_request_that_sends_a_token_prints_nothing
    body = %(curl -fsS "http://127.0.0.1:${PORT}/chat/metrics?token=${TOKEN}"\n) +
           %q(middleware.call(env.merge("QUERY_STRING" => "token=#{token}"))) + "\n" +
           %(puts "web: token set, /pair issue for a code"\n)

    assert_empty TokenEcho.echoes(body, "bin/smoke")
  end

  def test_no_tracked_script_prints_a_token_value
    failures = []
    TokenEcho.check(failures, ROOT)
    scripts = TokenEcho.candidates(ROOT)

    assert_empty failures
    assert_operator scripts.size, :>, 100, "the scan read almost nothing, so its silence is not a finding"
    assert_includes scripts, "OPENBSD/etc/rc.d/master"
  end

  def test_the_committed_start_block_passes_against_the_real_middleware
    failures = []
    check_master_rc(failures)

    assert_empty failures
    refute_empty auth_tier_public_paths, "AuthTier's public paths read as empty, so every warmup would fail"
  end

  def test_a_relayd_host_route_that_is_missing_is_named
    relayd = File.read(RELAYD)
    port = YAML.safe_load_file(APPS_YML).dig("apps", "brgen", "port")
    failures = []
    assert_forward(relayd.sub(/^\s*match request header "Host" value "brgen\.no" forward to <brgen>.*$/, ""),
                   failures, "brgen", port, "brgen.no")

    assert_equal ["relayd: missing Host route for brgen.no in brgen"], failures
  end

  def test_the_committed_tree_passes
    out, status = Open3.capture2e(RbConfig.ruby, File.join(OPENBSD, "deploy_smoke_gate.rb"))

    assert status.success?, out
  end
end
