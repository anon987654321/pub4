#!/usr/bin/env ruby
# frozen_string_literal: true

# VPS_SAFETY_ROOT lets the test point this at a fixture tree holding the shapes
# it must flag; unset, it reads this checkout.
ROOT = ENV.fetch("VPS_SAFETY_ROOT", File.expand_path("../..", __dir__))
OPENBSD = File.join(ROOT, "OPENBSD")
TOOLING = File.join(ROOT, "OPENBSD", "bin")
failures = []

doas_conf = File.join(OPENBSD, "etc", "doas.conf")
if File.file?(doas_conf)
  text = File.read(doas_conf)
  failures << "doas.conf must end with newline (OpenBSD parser rejects EOF without one)" unless text.end_with?("\n")

  rules = text.lines.reject { |line| line.strip.empty? || line.strip.start_with?("#") }
  dev_rule = rules.find { |line| line.match?(/\bdev\s+as\s+root\b/) }

  # keepenv on the dev rule is a root RCE by construction: it carries RUBYOPT,
  # RUBYLIB, GEM_HOME and BUNDLE_* across the boundary, so `RUBYOPT=-r/tmp/x.rb doas
  # <anything>` runs as root with no shell involved. Removed 2026-08-02 for a measured
  # setenv allowlist; this is what stops it coming back with the next edit that finds
  # a variable missing. The root->root rule keeps keepenv on purpose — see the file.
  if dev_rule.nil?
    failures << "etc/doas.conf has no `dev as root` rule"
  else
    failures << "etc/doas.conf: dev rule must not use keepenv (root RCE via RUBYOPT)" if dev_rule.include?("keepenv")
    # The whole measured allowlist (etc/doas.conf): each is read by a script run
    # under doas and assigned by none, so dropping one silently breaks that
    # script — --stage-1's DNS-wipe gate, the console gate, production seeds, the
    # deploy scan skip, the mail image format.
    allowlist = dev_rule[/setenv\s*\{([^}]*)\}/, 1].to_s.split
    %w[I_UNDERSTAND_DNS_WIPE I_UNDERSTAND_CONSOLE_RISK I_UNDERSTAND_FAST_DEPLOY RUN_PRODUCTION_SEEDS SKIP_MASTER_SCAN MAIL_IMG_FMT].each do |name|
      failures << "etc/doas.conf: dev rule must setenv-allowlist #{name}" unless allowlist.include?(name)
    end
  end
else
  failures << "missing tracked etc/doas.conf"
end

operator_script = File.join(OPENBSD, "OPERATOR.sh")
if File.file?(operator_script)
  operator = File.read(operator_script)
  unless operator.include?('[[ ${SKIP_MASTER_SCAN:-0} != 0 ]]') &&
         operator.include?('[[ ${SKIP_MASTER_SCAN} != 1 || ${I_UNDERSTAND_FAST_DEPLOY:-0} != 1 ]]')
    failures << "OPERATOR.sh: MASTER scan bypass requires SKIP_MASTER_SCAN=1 plus I_UNDERSTAND_FAST_DEPLOY=1"
  end
else
  failures << "missing tracked OPERATOR.sh"
end

validate_doas = File.join(TOOLING, "validate_doas.ksh")
if File.file?(validate_doas)
  # install_doas_conf_from_repo rolls /etc/doas.conf back when validation fails, so
  # validation has to test the thing that changed. `doas id` alone passes with a wrong
  # or empty allowlist — the rollback net covered lockout and not the actual risk.
  guard = File.read(validate_doas)
  unless guard.include?("validate_doas_passes_env")
    failures << "validate_doas.ksh must check that an allowlisted variable still crosses, " \
                "not only that dev can reach root"
  end
else
  failures << "missing OPENBSD/bin/validate_doas.ksh"
end

admin_path = File.join(OPENBSD, "usr", "local", "sbin", "pub4-admin")
if File.symlink?(admin_path)
  failures << "usr/local/sbin/pub4-admin must not be a symlink"
end
if File.file?(admin_path) && !File.symlink?(admin_path)
  admin = File.read(admin_path)
  broker_contract = admin.include?("def command_for(argv)") &&
                    admin.include?("exec(*command)") &&
                    admin.include?("SERVICE_ACTIONS") &&
                    admin.include?("SERVICES")
  failures << "pub4-admin must be a fixed-path closed broker" unless broker_contract
  task_app_scope = admin.include?("known_apps = helper == RAILS_TASK ? RAILS_TASK_APPS : RAILS_APPS") &&
                   admin.include?("RAILS_TASK_APPS = %w[master brgen amber bsdports].freeze")
  failures << "pub4-admin must validate each helper against its own app allowlist" unless task_app_scope
  safe_spawn = admin.include?('Process.spawn(environment, "/bin/ksh", helper, *arguments, **spawn_options)') &&
               admin.include?('raise "unknown helper" unless [CI_RUN, CI_SYNC, RAILS_TASK].include?(helper)') &&
               admin.include?("when RAILS_TASK then Array(helper_arguments)") &&
               admin.include?("when CI_RUN then [app, duration.to_s]") &&
               admin.include?("when CI_SYNC then [app]") &&
               admin.include?("spawn_options[:uid] = account.uid") &&
               admin.include?("spawn_options[:gid] = account.gid") &&
               admin.include?('trusted_script!(helper)')
  unsafe_spawn = admin.include?("Process.spawn") &&
                 (admin.scan("Process.spawn").length != 1 || !safe_spawn)
  failures << "pub4-admin must not evaluate shell command strings or widen its CI spawn" if
    admin.match?(/system\s*\(|Open3\.|%x/) || unsafe_spawn
  sync_path = File.join(OPENBSD, "usr", "local", "libexec", "ci-sync.ksh")
  if File.file?(sync_path)
    sync = File.read(sync_path)
    sync_contract = sync.include?("brgen|amber|bsdports") &&
                    sync.include?('repo=/home/dev/pub4') &&
                    sync.include?('[ "$(id -un)" = "$app" ]') &&
                    sync.include?('tar xf - -C "$app_dir"') &&
                    sync.scan('git -c safe.directory="$repo" -C "$repo"').length >= 3 &&
                    !sync.include?('git -C "$repo"') &&
                    !sync.match?(/^\s*(?:doas|sudo|chown)\b/)
    failures << "ci-sync helper must be app-scoped, pin one Git safe.directory and avoid privileged actions" unless sync_contract
  else
    failures << "missing tracked usr/local/libexec/ci-sync.ksh"
  end
  prepare_path = File.join(OPENBSD, "usr", "local", "libexec", "ci-prepare.ksh")
  if File.file?(prepare_path)
    prepare = File.read(prepare_path)
    prepare_contract = prepare.include?("brgen|amber|bsdports") &&
                       prepare.include?('[ ! -L "$app_home" ]') &&
                       prepare.include?('[ ! -L "$app_dir" ]') &&
                       prepare.include?('[ "$(stat -f %u "$storage")" = "$app_uid" ]') &&
                       prepare.include?('storage="$app_dir/storage"')
    failures << "ci-prepare helper must check app-owned real path components before chmod" unless prepare_contract
  else
    failures << "missing tracked usr/local/libexec/ci-prepare.ksh"
  end

  rails_task_path = File.join(OPENBSD, "usr", "local", "libexec", "rails-task.ksh")
  if File.file?(rails_task_path) && !File.symlink?(rails_task_path)
    rails_task = File.read(rails_task_path)
    rails_task_secret_contract = admin.include?('environment["SECRET_KEY_BASE"] = environment_secret if environment_secret') &&
                              admin.include?("environment_secret = app_secret_value(app)") &&
                              rails_task.include?("export SECRET_KEY_BASE") &&
                              !rails_task.include?('command="SECRET_KEY_BASE=$secret')
    failures << "Rails task secrets must use the child environment, never command arguments" unless rails_task_secret_contract
    rails_task_contract = rails_task.include?("master|brgen|amber|bsdports") &&
                          rails_task.include?("overlay-initializers|overlay-public") &&
                          rails_task.include?("bundle-install|bundle-check|ci-bundle-install|db-prepare|db-seed|assets-precompile|ci") &&
                          rails_task.include?("db-storage-migrate)") &&
                          rails_task.include?('[ ! -L db ]') &&
                          rails_task.include?('[ ! -L storage ]') &&
                          rails_task.include?("cache|queue|cable") &&
                          rails_task.include?("secondary-db-check)") &&
                          rails_task.include?('table=$("$ruby_path" -e') &&
                          rails_task.include?('[ ! -L "$app_home" ]') &&
                          rails_task.include?('[ ! -L "$app_dir" ]') &&
                          rails_task.include?('[ ! -L "$app_dir/db" ]') &&
                          rails_task.include?('[ ! -L "$app_dir/storage" ]') &&
                          rails_task.include?('exec /usr/bin/su -m "$app" -c "$script"') &&
                          rails_task.include?('unset BUNDLE_GEMFILE BUNDLE_PATH BUNDLE_BIN_PATH BUNDLE_WITH BUNDLE_WITHOUT')
    failures << "rails-task helper must expose only fixed task names and execute as the app user" unless rails_task_contract
  else
    failures << "missing or symlinked tracked usr/local/libexec/rails-task.ksh"
  end

  runner_path = File.join(OPENBSD, "usr", "local", "libexec", "ci-run.ksh")
  if File.file?(runner_path)
    runner = File.read(runner_path)
    runner_contract = runner.include?("brgen|amber|bsdports") &&
                      runner.include?('[ "$timeout" -ge 1 ] && [ "$timeout" -le 7200 ]') &&
                      runner.include?('cd /home/$app/app') &&
                      runner.include?('exec /usr/bin/su -m "$app" -c "$script"') &&
                      runner.include?('/usr/local/bin/bundle') &&
                      runner.include?('unset RUBYOPT RUBYLIB RUBYPATH RUBYGEMS_GEMDEPS GEM_HOME GEM_PATH')
    failures << "ci-run helper must use fixed app paths, bounded timeout and sanitized Ruby environment" unless runner_contract
  else
    failures << "missing tracked usr/local/libexec/ci-run.ksh"
  end

  relay_adapter_path = File.join(ROOT, "RAILS", "_service.sh")
  if File.file?(relay_adapter_path)
    relay_adapter = File.read(relay_adapter_path)[/relayd_add_relay\(\) \{.*?^\}/m]
    relay_adapter_contract = relay_adapter &&
                            relay_adapter.include?('pub4-admin relayd-check "$app" "$domain" "$port"') &&
                            relay_adapter.include?("fixed broker is missing; run OPERATOR.sh") &&
                            !relay_adapter.match?(/\$\{_PRIV\}.*\$RUBY/)
    failures << "relayd deploy adapter must use the broker and refuse unsafe fallback" unless relay_adapter_contract
  else
    failures << "missing RAILS/_service.sh relayd broker adapter"
  end
  runtime_path = File.join(ROOT, "RAILS", "_runtime_gate.sh")
  if File.file?(runtime_path)
    runtime = File.read(runtime_path)
    runner = runtime[/run_rails_as_app\(\) \{.*?^\}/m]
    runner_contract = runner &&
                     runner.include?('[[ -x /usr/local/sbin/pub4-admin ]]') &&
                     runner.include?('/usr/local/sbin/pub4-admin rails-task "$app_name" "$task"') &&
                     runner.include?("pub4-admin is missing; run OPERATOR.sh before deploying") &&
                     !runner.match?(/\$\{_PRIV\}\s+sh\s+-c/) &&
                     !runner.include?("su -m")
    failures << "rails runtime task runner must fail closed without the broker" unless runner_contract
  else
    failures << "missing RAILS/_runtime_gate.sh task runner"
  end
  relayd_contract = admin.include?('args.length == 4 && args[0] == "relayd-check"') &&
                    admin.include?("def relayd_check(app, domain, requested_port)") &&
                    admin.include?("File.lstat(RELAYD_CONFIG)") &&
                    admin.include?('no operator-approved Host route for #{domain}') &&
                    admin.include?("requested port does not match the root-configured backend") &&
                    !admin.include?("def relayd_add(app, domain, requested_port)") &&
                    !admin.include?("File.rename(temporary, RELAYD_CONFIG)") &&
                    !admin.match?(/IO\.popen\(\s*["']/)
  failures << "relayd broker must be verification-only and reject unapproved Host routes" unless relayd_contract
  secret_dispatch = admin.include?('args[0] == "ensure-secret" && APPS.include?(args[1])') &&
                  admin.include?("def ensure_app_secret(app)") &&
                  admin.include?("File::CREAT | File::EXCL") &&
                  admin.include?("File.rename(temporary, target)") &&
                  admin.include?("already exists without a valid SECRET_KEY_BASE; refusing to replace the environment file")
  failures << "pub4-admin must create secrets only at fixed app paths and atomically" unless secret_dispatch

  broker_helper_dispatch = admin.include?('args[0] == "ci-prepare" && RAILS_APPS.include?(args[1])') &&
                           admin.include?('args[0] == "ci-run" && RAILS_APPS.include?(args[1])') &&
                           admin.include?('args[0] == "ci-sync" && RAILS_APPS.include?(args[1])') &&
                           admin.include?('trusted_script!(CI_PREPARE)') &&
                           admin.include?('trusted_script!(CI_RUN)') &&
                           admin.include?('supervised_helper(CI_SYNC, app, 900)') &&
                           admin.include?('args[0] == "rails-task" && RAILS_TASK_APPS.include?(args[1])') &&
                           admin.include?('run_rails_task(args[1], args[2])') &&
                           admin.include?('supervised_helper(RAILS_TASK, app, 7200, arguments)') &&
                           admin.include?('args[0] == "retire-legacy"') &&
                           admin.include?('def legacy_service_name(app)') &&
                           admin.include?('File.lstat(path)')
  failures << "pub4-admin must expose only fixed app-scoped CI helper verbs" unless broker_helper_dispatch

  installer = File.read(File.join(OPENBSD, "OPERATOR.sh"))
  source_preflight = installer.include?("typeset -a privileged_sources=(") &&
                     installer.include?('if [[ ! -f $src/$rel || -L $src/$rel ]]') &&
                     installer.include?("missing or symlinked privileged source")
  failures << "OPERATOR.sh must preflight privileged sources before copying" unless source_preflight
  install_preflight = installer.include?("installed privileged entrypoint missing or symlinked") &&
                      installer.include?("/usr/local/libexec/pub4/solid_queue_proof.rb")
  failures << "OPERATOR.sh must verify installed privileged entrypoints" unless install_preflight
  destination_guard_at = installer.index("Never copy privileged code through a symlinked system directory or file.")
  copy_loop_at = installer.index("for d in etc usr var; do")
  destination_preflight = installer.include?("refusing symlinked privileged destination directory") &&
                          installer.include?("refusing symlinked privileged destination file") &&
                          destination_guard_at && copy_loop_at && destination_guard_at < copy_loop_at
  failures << "OPERATOR.sh must refuse symlinked privileged destinations before copying" unless destination_preflight
  installs_after_copy = installer.include?("installed Solid Queue proof is missing or symlinked") &&
                        installer.include?("installed resource guard is missing or symlinked")
  failures << "OPERATOR.sh must verify installed helpers after their explicit install" unless installs_after_copy
  installer_pins_admin = installer.include?("chown root:wheel /usr/local/sbin/pub4-admin") &&
                         installer.include?("chmod 555 /usr/local/sbin/pub4-admin") &&
                         installer.include?("[[ -L $f ]]") &&
                         installer.include?("/usr/local/libexec/ci-sync.ksh") &&
                         installer.include?("/usr/local/libexec/rails-task.ksh")
  failures << "OPERATOR.sh must reject symlinked privileged entrypoints and install pub4-admin root-owned/non-writable" unless installer_pins_admin
else
  failures << "missing tracked usr/local/sbin/pub4-admin"
end

%w[ci-prepare.ksh ci-run.ksh ci-sync.ksh rails-task.ksh].each do |name|
  path = File.join(OPENBSD, "usr", "local", "libexec", name)
  failures << "usr/local/libexec/#{name} must not be a symlink" if File.symlink?(path)
end
console_main = File.join(TOOLING, "vps_console.exp")
if File.file?(console_main)
  text = File.read(console_main)
  unless text.include?("proc require_console_risk_ack") && text.match?(/^require_console_risk_ack$/)
    failures << "OPENBSD/bin/vps_console.exp must define and call require_console_risk_ack"
  end
  failures << "OPENBSD/bin/vps_console.exp must target vm23 only (found vm27)" if text.include?("vm27")
else
  failures << "missing OPENBSD/bin/vps_console.exp"
end

# vps_console.exp is the one console door, and the ack inside it is the whole
# safety. Any other expect script beside it is a way to the console that
# skipped that check, so it fails here rather than being trusted to delegate.
Dir.glob(File.join(TOOLING, "*.exp")).reject { |path| path == console_main }.each do |path|
  failures << "OPENBSD/bin/#{File.basename(path)}: console automation belongs in vps_console.exp as a mode"
end

Dir.glob(File.join(OPENBSD, "etc", "rc.d", "*")).sort.each do |path|
  next unless File.file?(path)

  text = File.read(path)
  rel = path.delete_prefix("#{ROOT}/")
  if text.include?("falcon serve") && !text.match?(/\${_bundle} exec falcon/)
    failures << "#{rel} must invoke falcon via ${_bundle} exec (gem binstub, not PATH)"
  end
end

if failures.any?
  warn "VPS safety gate failures:"
  failures.each { |failure| warn "  - #{failure}" }
  exit 1
end

puts "VPS safety gate passed (doas.conf, console guards, validate_doas.ksh, rc.d falcon)."
