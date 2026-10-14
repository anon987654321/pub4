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

guard_wrapper_path = File.join(OPENBSD, "bin", "resource_guard.sh")
guard_impl_path = File.join(OPENBSD, "usr", "local", "bin", "resource_guard.sh")
if File.file?(guard_wrapper_path) && !File.symlink?(guard_wrapper_path) &&
   File.file?(guard_impl_path) && !File.symlink?(guard_impl_path)
  guard_wrapper = File.read(guard_wrapper_path)
  guard_impl = File.read(guard_impl_path)
  guard_wrapper_contract = guard_wrapper.include?('if [ "$(id -u)" -eq 0 ]; then') &&
                          guard_wrapper.include?('runner=/usr/local/bin/resource_guard.sh') &&
                          guard_wrapper.include?('exec doas "$runner"') &&
                          !guard_wrapper.match?(/^\s*(?:rcctl|install|chmod|chown)\s/m)
  failures << "checkout resource-guard entrypoint must refuse root and delegate to installed runner" unless guard_wrapper_contract
  guard_impl_contract = guard_impl.include?('GUARD_HELPER=/usr/local/libexec/stale_ci_cleanup.ksh') &&
                        guard_impl.include?('[[ -f $GUARD_HELPER && ! -L $GUARD_HELPER ]]') &&
                        !guard_impl.include?("GUARD_REPO") &&
                        !guard_impl.include?("/home/dev/pub4/OPENBSD/usr/local/libexec/stale_ci_cleanup.ksh")
  failures << "root load guard must be separate from its checkout wrapper and reject symlinked helpers" unless guard_impl_contract
  operator = File.read(File.join(OPENBSD, "OPERATOR.sh"))
  source_list = operator[/typeset -a privileged_sources=\(.*?^  \)/m].to_s
  guard_install_contract = source_list.include?("usr/local/bin/resource_guard.sh") &&
                          operator.include?('install -o root -g wheel -m 555 "${src}/usr/local/bin/resource_guard.sh" /usr/local/bin/resource_guard.sh') &&
                          operator.include?('refusing symlinked privileged destination file: $rel') &&
                          operator.include?('installed resource guard is missing or symlinked')
  failures << "OPERATOR.sh must preflight, install, and verify the root-owned load guard" unless guard_install_contract
else
  failures << "missing or symlinked resource-guard wrapper/runner source"
end

emergency_wrapper_path = File.join(OPENBSD, "emergency_cpu.sh")
emergency_impl_path = File.join(OPENBSD, "usr", "local", "bin", "emergency_cpu.sh")
if File.file?(emergency_wrapper_path) && !File.symlink?(emergency_wrapper_path) &&
   File.file?(emergency_impl_path) && !File.symlink?(emergency_impl_path)
  emergency_wrapper = File.read(emergency_wrapper_path)
  emergency_impl = File.read(emergency_impl_path)
  wrapper_contract = emergency_wrapper.include?('if [ "$(id -u)" -eq 0 ]; then') &&
                     emergency_wrapper.include?('exec doas "$runner"') &&
                     emergency_wrapper.include?('runner=/usr/local/bin/emergency_cpu.sh') &&
                     !emergency_wrapper.include?("stale_ci_cleanup") &&
                     !emergency_wrapper.match?(/^\s*(?:rcctl|pkill)\b/m)
  failures << "checkout emergency CPU entrypoint must refuse root and delegate to installed runner" unless wrapper_contract
  runner_contract = emergency_impl.include?('GUARD_HELPER=/usr/local/libexec/stale_ci_cleanup.ksh') &&
                    emergency_impl.include?('[[ -f $GUARD_HELPER && ! -L $GUARD_HELPER ]]') &&
                    !emergency_impl.include?("GUARD_REPO") &&
                    !emergency_impl.include?("/home/dev/pub4/OPENBSD/usr/local/libexec/stale_ci_cleanup.ksh")
  failures << "emergency CPU runner must not source stale cleanup from checkout" unless runner_contract
  installer = File.read(File.join(OPENBSD, "OPERATOR.sh"))
  source_list = installer[/typeset -a privileged_sources=\(.*?^  \)/m].to_s
  emergency_install_contract = source_list.include?("usr/local/bin/emergency_cpu.sh") &&
                               installer.include?("usr/local/bin/emergency_cpu.sh") &&
                              installer.include?('install -o root -g wheel -m 555 "${src}/usr/local/bin/emergency_cpu.sh" /usr/local/bin/emergency_cpu.sh') &&
                              installer.include?('refusing symlinked privileged destination file: $rel') &&
                              installer.include?('installed emergency CPU runner is missing or symlinked')
  failures << "OPERATOR.sh must preflight, install, and verify the root-owned emergency runner" unless emergency_install_contract
else
  failures << "missing or symlinked emergency CPU wrapper/runner source"
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
  failures << "pub4-admin must use the fixed packaged Ruby interpreter" unless
    admin.start_with?("#!/usr/local/bin/ruby\n")
  status_contract = admin.include?('args.length == 4 && args[0] == "deploy-status"') &&
                    admin.include?("def write_deploy_status(app, step, state)") &&
                    admin.include?('File.join(directory, "#{app}.json")') &&
                    admin.include?("File.link(temporary, target)") &&
                    admin.include?('raise "#{target} is a symlink; refusing status write"')
  failures << "deploy-status writes must use the atomic fixed-path broker" unless status_contract
  disk_usage_contract = admin.include?('DISK_USAGE_PATHS = %w[/home /var].freeze') &&
                       admin.include?('return [DU, "-xk", args[1]] if args.length == 2 && args[0] == "disk-usage" && DISK_USAGE_PATHS.include?(args[1])')
  failures << "pub4-admin disk usage must be restricted to deploy mount roots" unless disk_usage_contract
  master_web_contract = admin.include?('MASTER_WEB_ROOT = "/home/dev/pub4/RAILS/master"') &&
                       admin.include?('args == ["master-web-assets-reset"]') &&
                       admin.include?('args == ["master-web-runtime-dirs"]') &&
                       admin.include?("def master_web_root!") &&
                       admin.include?("def master_web_tree_paths!(root)") &&
                       admin.include?("Find.find(root)") &&
                       admin.include?("raise \"symlink refused in MASTER web path: #{path}\" if stat.symlink?")
  failures << "master-web helper must be fixed-path and symlink-safe" unless master_web_contract
  broker_contract = admin.include?("def command_for(argv)") &&
                    admin.include?("exec(*command)") &&
                    admin.include?("SERVICE_ACTIONS") &&
                    admin.include?("SERVICES")
  failures << "pub4-admin must be a fixed-path closed broker" unless broker_contract
  task_app_scope = admin.include?("known_apps = helper == RAILS_TASK ? RAILS_TASK_APPS : RAILS_APPS") &&
                   admin.include?("RAILS_TASK_APPS = %w[master brgen amber bsdports].freeze")
  failures << "pub4-admin must validate each helper against its own app allowlist" unless task_app_scope
  safe_spawn = admin.include?('Process.spawn(environment, "/bin/ksh", helper, *arguments, **spawn_options)') &&
               admin.include?('raise "unknown helper" unless [CI_RUN, CI_SYNC, RAILS_TASK, RAILS_SYNC].include?(helper)') &&
               admin.include?("when RAILS_TASK then Array(helper_arguments)") &&
               admin.include?("when CI_RUN then [app, duration.to_s]") &&
               admin.include?("when CI_SYNC then [app]") &&
               admin.include?("when RAILS_SYNC then [app, *Array(helper_arguments)]") &&
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
    group_create_at = prepare.index("/usr/sbin/groupadd _pub4ci")
    usermod_at = prepare.index("/usr/sbin/usermod -G _pub4ci \"$app\"")
    chgrp_at = prepare.index("/bin/chgrp _pub4ci /home/dev")
    unless group_create_at && usermod_at && chgrp_at && group_create_at < usermod_at && usermod_at < chgrp_at
      failures << "ci-prepare must create _pub4ci and enroll the app before chgrp"
    end
  end
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
                          rails_task.include?("bundle-cache-prepare") &&
                          rails_task.include?("export PUB4_TASK_RUBY=$ruby_path") &&
                          rails_task.include?('ruby_version=$("$PUB4_TASK_RUBY" -e "print RUBY_VERSION.split(46.chr).first(2).join")') &&
                          rails_task.include?('npm-cache)') &&
                          rails_task.include?('command="mkdir -p /home/$app/.npm /home/$app/.cache"') &&
                          rails_task.include?("bundle-cas-hydrate)") &&
                          rails_task.include?('cp "$source" "$target"') &&
                          rails_task.include?('export PUB4_TASK_CACHE_KEY=$database') &&
                          rails_task.include?("db-storage-migrate)") &&
                          rails_task.include?('[ ! -L db ]') &&
                          rails_task.include?('[ ! -L storage ]') &&
                          rails_task.include?("cache|queue|cable") &&
                          rails_task.include?("secondary-db-check)") &&
                          rails_task.include?('table=$("$ruby_path" -e') &&
                          rails_task.include?('[ ! -L /home ]') &&
                          rails_task.include?('[ ! -L "$app_home" ]') &&
                          rails_task.include?('[ ! -L "$app_dir" ]') &&
                          rails_task.include?('app_bundle="$app_dir/.bundle"') &&
                          rails_task.include?('[ ! -L "$app_bundle" ]') &&
                          rails_task.include?('[ ! -L "$app_dir/db" ]') &&
                          rails_task.include?('[ ! -L "$app_dir/storage" ]') &&
                          rails_task.include?('exec /usr/bin/su -m "$app" -c "$script"') &&
                          rails_task.end_with?("exec /usr/bin/su -m \"$app\" -c \"$script\"\\n") &&
                          rails_task.scan('exec /usr/bin/su -m "$app" -c "$script"').length == 1 &&
                          !rails_task.include?("EOF_KEY") &&
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
  sync_file = File.join(ROOT, "RAILS", "_sync.sh")
  if File.file?(sync_file)
    sync_source = File.read(sync_file)
    initializers_overlay = sync_source[/overlay_shared_initializers\(\) \{.*?^\}/m]
    public_overlay = sync_source[/overlay_shared_public\(\) \{.*?^\}/m]
    overlay_contract = initializers_overlay &&
                       initializers_overlay.include?('run_rails_as_app "$app_name" "$app_dir" "overlay-initializers"') &&
                       !initializers_overlay.match?(/\$\{_PRIV\}\s+(?:mkdir|cp|rm|mv)/) &&
                       public_overlay &&
                       public_overlay.include?('run_rails_as_app "$app_name" "$app_dir" "overlay-public"') &&
                       !public_overlay.match?(/\$\{_PRIV\}\s+(?:mkdir|cp|rm|mv)/)
    failures << "shared Rails overlays must run as the app user through fixed Rails tasks" unless overlay_contract
  else
    failures << "missing RAILS/_sync.sh shared overlay adapters"
  end

  deploy_path = File.join(ROOT, "RAILS", "_deploy.sh")
  if File.file?(deploy_path)
    deploy = File.read(deploy_path)
    access_at = deploy.index('pub4-admin ci-prepare "$app_name"')
    app_sync_at = deploy.index('rails_sync_app_tree "$app_name" app')
    shared_sync_at = deploy.index('rails_sync_app_tree "$app_name" shared')
    overlay_at = deploy.index('overlay_shared_initializers "$APP_DIR"')
    end_at = deploy.index('deploy_status "$app_name" "master scan"')
    sync_block = app_sync_at && end_at ? deploy[app_sync_at...end_at] : ""
    ordered = access_at && app_sync_at && shared_sync_at && overlay_at && end_at &&
              access_at < app_sync_at && app_sync_at < shared_sync_at && shared_sync_at < overlay_at
    unless ordered && !sync_block.match?(/doas (?:rm|chown|mkdir|mv|sh -c)/)
      failures << "production Rails tree sync must use the fixed app-user broker after ci-prepare"
    end
  else
    failures << "missing RAILS/_deploy.sh app-user sync path"
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
  ci_lock_contract = admin.include?('return ensure_ci_lock if args == ["ci-lock"]') &&
                    admin.include?('path = File.join(STAMP_DIR, "ci.lock")') &&
                    admin.include?('raise "#{path} is not a regular file" unless lock.file? && !lock.symlink?')
  failures << "pub4-admin CI lock must use one fixed path and refuse symlinks" unless ci_lock_contract

  secret_dispatch = admin.include?('args[0] == "ensure-secret" && APPS.include?(args[1])') &&
                  admin.include?("def ensure_app_secret(app, emit: true)") &&
                  admin.include?("ensure_app_secret(app, emit: false)") &&
                  admin.include?("File::CREAT | File::EXCL") &&
                  admin.include?("File.link(temporary, target)") &&
                  admin.include?("already exists without a valid SECRET_KEY_BASE; refusing to replace the environment file")
  failures << "pub4-admin must create secrets only at fixed app paths and atomically" unless secret_dispatch

  bundle_cache_contract = admin.include?('args.length == 4 && args[0] == "bundle-cache"') &&
                         admin.include?("def bundle_cache(app, action, ruby_key)") &&
                         admin.include?('BUNDLE_CACHE_BASE = "/var/cache/pub4/bundle"') &&
                         admin.include?('%w[prepare import capture].include?(action)') &&
                         admin.include?("File.link(temporary, target)") &&
                         admin.include?("File::CREAT | File::EXCL") &&
                         admin.include?("valid_ruby_cache_key?(ruby_key)") &&
                         admin.include?("bundle cache import exceeds 500 files")
  failures << "pub4-admin bundle cache must be immutable and fixed-path" unless bundle_cache_contract
  bundle_shell_path = File.join(ROOT, "RAILS", "_bundle.sh")
  if File.file?(bundle_shell_path)
    bundle_shell = File.read(bundle_shell_path)
    cas_prepare = bundle_shell[/bundle_cas_prepare\(\) \{.*?^\}/m]
    cas_capture = bundle_shell[/bundle_cas_capture\(\) \{.*?^\}/m]
    bundle_cas_shell_contract = cas_prepare && cas_capture &&
                               cas_prepare.include?('pub4-admin bundle-cache "$app_name" prepare "$RUBY_CACHE_KEY"') &&
                               cas_prepare.include?('pub4-admin bundle-cache "$app_name" import "$RUBY_CACHE_KEY"') &&
                               cas_prepare.include?('run_rails_as_app "$app_name" "$app_dir" "bundle-cas-hydrate" "$RUBY_CACHE_KEY"') &&
                               cas_capture.include?('pub4-admin bundle-cache "$app_name" capture "$RUBY_CACHE_KEY"') &&
                               ![cas_prepare, cas_capture].any? { |body| body.match?(/\$\{_PRIV\}\s+(?:mkdir|cp|ln|chown)\b/) }
    failures << "Rails Bundler CAS wrappers must use the fixed broker and avoid privileged path operations" unless bundle_cas_shell_contract
  else
    failures << "missing RAILS/_bundle.sh CAS adapters"
  end
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

  rails_sync_path = File.join(OPENBSD, "usr", "local", "libexec", "rails-sync.ksh")
  if File.file?(rails_sync_path) && !File.symlink?(rails_sync_path)
    rails_sync = File.read(rails_sync_path)
    sync_contract = rails_sync.include?("app|shared") &&
                    rails_sync.include?("verticals") &&
                    rails_sync.include?('[ "$(id -un)" = "$app" ]') &&
                    rails_sync.include?('sync_tree_stage "$rails_root/$app" "$app_dir" yes') &&
                    rails_sync.include?('git -c safe.directory="$repo" -C "$repo" archive HEAD "RAILS/$source_rel"') &&
                    rails_sync.include?('archive_tracked_tree "$source_dir" "$stage"') &&
                    !rails_sync.include?('tar cf - -C "$source_dir" .') &&
                    rails_sync.include?('for state in storage log; do') &&
                    rails_sync.include?('if [ "$state" = storage ]; then storage_carried=1; fi') &&
                    rails_sync.include?('if [ "$state" = log ]; then log_carried=1; fi') &&
                    rails_sync.include?('public/assets') &&
                    !rails_sync.match?(/^\s*(?:doas|sudo|chown)\b/)
    failures << "rails-sync helper must be app-owned, fixed-mode and preserve runtime state" unless sync_contract
  else
    failures << "missing or symlinked tracked usr/local/libexec/rails-sync.ksh"
  end
  installer = File.read(File.join(OPENBSD, "OPERATOR.sh"))
  source_preflight = installer.include?("typeset -a privileged_sources=(") &&
                     installer.include?('if [[ ! -f $src/$rel || -L $src/$rel ]]') &&
                     installer.include?("missing or symlinked privileged source")
  failures << "OPERATOR.sh must preflight privileged sources before copying" unless source_preflight
  install_preflight = installer.include?("installed privileged entrypoint missing or symlinked") &&
                      installer.include?("/usr/local/libexec/rails-sync.ksh; do") &&
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
                         installer.include?("/usr/local/libexec/rails-task.ksh") &&
                         installer.include?("/usr/local/libexec/rails-sync.ksh")
  failures << "OPERATOR.sh must reject symlinked privileged entrypoints and install pub4-admin root-owned/non-writable" unless installer_pins_admin
else
  failures << "missing tracked usr/local/sbin/pub4-admin"
end

%w[ci-prepare.ksh ci-run.ksh ci-sync.ksh rails-task.ksh rails-sync.ksh].each do |name|
  path = File.join(OPENBSD, "usr", "local", "libexec", name)
  failures << "usr/local/libexec/#{name} must not be a symlink" if File.symlink?(path)
end
smoke_source = File.read(File.join(OPENBSD, "bin", "deploy-smoke.sh"))
smoke_contract = smoke_source.include?('case "$svc" in master|brgen|amber|bsdports|relayd)') &&
                 smoke_source.include?('doas /usr/local/sbin/pub4-admin service check "$svc"') &&
                 smoke_source.include?('if [ -L /usr/local/sbin/pub4-admin ]; then') &&
                 smoke_source.include?("Bootstrap fallback only")
failures << "deploy-smoke service checks must use the fixed broker and an explicit fallback" unless smoke_contract
install_all_source = File.read(File.join(OPENBSD, "bin", "vps_install_all.sh"))
install_all_contract = install_all_source.include?("admin_service() {") &&
                       install_all_source.include?('case "$action" in check|start|stop|restart)') &&
                       install_all_source.include?('case "$service" in master|brgen|amber|bsdports)') &&
                       install_all_source.include?('doas /usr/local/sbin/pub4-admin service "$action" "$service"') &&
                       install_all_source.include?('doas rcctl "$action" "$service"') &&
                       install_all_source.include?("Bootstrap fallback only") &&
                       install_all_source.include?('case "$app" in brgen|amber|bsdports)')
failures << "vps_install_all service control must be broker-first and app-allowlisted" unless install_all_contract
deploy_all_source = File.read(File.join(OPENBSD, "bin", "deploy_all.sh"))
deploy_all_contract = deploy_all_source.include?('zsh OPENBSD/bin/vps-deploy ${app}') &&
                      !deploy_all_source.include?('doas zsh ${script}') &&
                      !deploy_all_source.include?('RAILS/${app}/${app}.sh')
failures << "deploy_all per-app mode must not elevate checkout Rails wrappers" unless deploy_all_contract
start_all_apps_path = File.join(OPENBSD, "bin", "start_all_apps.sh")
if File.file?(start_all_apps_path)
  start_all_apps = File.read(start_all_apps_path)
  start_all_wrapper = start_all_apps.include?('if [ "$(id -u)" -eq 0 ]; then') &&
                      start_all_apps.include?('doas "$broker" start-all-apps') &&
                      start_all_apps.include?('health_check.rb" --all-ready-apps') &&
                      !start_all_apps.match?(/^\s*(?:rcctl|install|chmod|chown)\s/m)
  start_all_broker = admin.include?('return start_all_apps if args == ["start-all-apps"]') &&
                     admin.include?("def start_all_apps") &&
                     admin.include?('flag = "/var/db/pub4_all_apps"') &&
                     admin.include?('File::CREAT | File::EXCL') &&
                     admin.include?('services = ["master", *RAILS_APPS]') &&
                     admin.include?('call_rcctl("restart", "relayd")')
  failures << "start_all_apps wrapper and broker must be fixed and non-root" unless start_all_wrapper && start_all_broker
else
  failures << "missing OPENBSD/bin/start_all_apps.sh"
end
vps_state_path = File.join(OPENBSD, "bin", "vps-state")
if File.file?(vps_state_path)
  vps_state = File.read(vps_state_path)
  service_state = vps_state[/def service_state\(service\).*?^end/m]
  state_contract = service_state &&
                   service_state.include?('"doas", "-n", broker, "service", "check", service') &&
                   service_state.include?('return "unknown (pub4-admin missing)" unless File.file?(broker)') &&
                   !service_state.include?('"/usr/sbin/rcctl", "check", service')
  failures << "vps-state service reads must use the root broker" unless state_contract
else
  failures << "missing OPENBSD/bin/vps-state"
end

restore_litestream_path = File.join(OPENBSD, "bin", "restore_litestream.sh")
if File.file?(restore_litestream_path)
  restore_litestream = File.read(restore_litestream_path)
  restore_contract = restore_litestream.include?('doas /usr/local/sbin/pub4-admin service stop "$app"') &&
                     restore_litestream.include?('doas /usr/local/sbin/pub4-admin service start "$app"') &&
                     restore_litestream.include?('doas /usr/local/sbin/pub4-admin service check "$app"') &&
                     !restore_litestream.match?(/doas rcctl (?:stop|start|check)/)
  failures << "Litestream recovery must use brokered service control" unless restore_contract
else
  failures << "missing OPENBSD/bin/restore_litestream.sh"
end
manual_master_path = File.join(OPENBSD, "bin", "manual_master_deploy.ksh")
if File.file?(manual_master_path)
  manual_master = File.read(manual_master_path)
  manual_master_contract = manual_master.include?("pub4-admin service stop master") &&
                           manual_master.include?("pub4-admin service restart master") &&
                           manual_master.include?("pub4-admin service restart relayd") &&
                           manual_master.include?("pub4-admin missing or symlinked") &&
                           !manual_master.match?(/^\s*doas\s+rcctl\b/)
  failures << "manual MASTER recovery must use brokered service control" unless manual_master_contract
else
  failures << "missing OPENBSD/bin/manual_master_deploy.ksh"
end
master_deploy_path = File.join(OPENBSD, "bin", "vps_deploy_master.sh")
if File.file?(master_deploy_path)
  master_deploy = File.read(master_deploy_path)
  master_deploy_contract = master_deploy.include?("pub4-admin master-web-assets-reset") &&
                           master_deploy.include?("pub4-admin master-web-runtime-dirs") &&
                           master_deploy.include?("pub4-admin service restart master") &&
                           master_deploy.include?('if [ "$ROOT" != "/home/dev/pub4" ]; then') &&
                           admin.include?("MASTER_WEB_ROOT.split(File::SEPARATOR)") &&
                           master_deploy.include?("cmp -s \"$ROOT/OPENBSD/etc/rc.d/master\" /etc/rc.d/master") &&
                           !master_deploy.include?("doas rm -rf public/assets") &&
                           !master_deploy.include?("doas chown -R dev:dev public") &&
                           !master_deploy.include?("doas install -d -o dev -g master") &&
                           !master_deploy.include?("doas cp \"$ROOT/OPENBSD/etc/rc.d/master\" /etc/rc.d/master")
  failures << "MASTER web deploy must use fixed broker verbs and refuse root-installing checkout rc.d" unless master_deploy_contract
else
  failures << "missing OPENBSD/bin/vps_deploy_master.sh"
end
deploy_source = File.read(File.join(OPENBSD, "bin", "vps-deploy"))
failures << "vps-deploy must not recommend generic privileged du" unless
  deploy_source.include?('pub4-admin disk-usage $mount_point') && !deploy_source.include?("doas du -xk $mount_point")
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
