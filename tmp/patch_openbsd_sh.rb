# encoding: utf-8
# frozen_string_literal: true

path = "/home/dev/pub4/MASTER/DEPLOY/openbsd/openbsd.sh"
content = File.read(path, encoding: "utf-8")

# Fix 1: Ruby 3.3 -> 3.4 everywhere
content.gsub!("ruby/3.3/", "ruby/3.4/")
content.gsub!("ruby%3.3", "ruby%3.4")
puts "1. ruby 3.3 -> 3.4"

# Fix 2: Replace the masterweb rc.d block with the working 'master' rc.d
# that includes API key injection
old_master_block = <<~'OLD'
  # Deploy MASTER web UI (ai.brgen.no -> port 3000)
  if ! is_step_completed "master_deployed"; then
    log INFO "Deploying MASTER web UI"
    typeset m3dir="/home/dev/pub4/MASTER"
    [[ -d $m3dir ]] || { log ERROR "MASTER not found at $m3dir"; exit 1 }
    cd "$m3dir/web"
    bundle config set --local path vendor/bundle
    bundle install --quiet
    rcctl enable masterweb
        cat > /etc/rc.d/masterweb <<RCEOF
#!/bin/ksh
daemon="/usr/local/bin/bundle"
daemon_flags="exec env RAILS_ENV=production SECRET_KEY_BASE_DUMMY=1 falcon serve --bind http://127.0.0.1:10002"
daemon_user="dev"
daemon_execdir="/home/dev/pub4/MASTER/web"
daemon_timeout="90"
. /etc/rc.d/rc.subr
pexp="ruby.*MASTER/web.*falcon"
rc_bg=YES
rc_reload=NO
rc_cmd \$1
RCEOF
    chmod 555 /etc/rc.d/masterweb
    rcctl start masterweb
    mark_step_completed "master_deployed"
    log INFO "MASTER web UI running on :3000"
  fi
OLD

new_master_block = <<~'NEW'
  # Deploy MASTER web UI (ai.brgen.no -> port 3000 via relayd -> 10002)
  if ! is_step_completed "master_deployed"; then
    log INFO "Deploying MASTER web UI"
    typeset m3dir="/home/dev/pub4/MASTER"
    [[ -d $m3dir ]] || { log ERROR "MASTER not found at $m3dir"; exit 1 }
    cd "$m3dir/web"
    bundle config set --local path vendor/bundle
    bundle install --quiet

    # Read API keys from dev's .zshrc for the rc.d service
    typeset env_line=""
    while IFS= read -r _line; do
      [[ $_line == export\ *_API_KEY=* ]] && {
        typeset _k=${_line#export }
        env_line="$env_line ${_k%%=*}=${${_k#*=}//[\"\']}"
      }
    done < /home/dev/.zshrc

    cat > /etc/rc.d/master <<RCEOF
#!/bin/ksh
daemon="/usr/local/bin/bundle"
daemon_flags="exec env RAILS_ENV=production SECRET_KEY_BASE_DUMMY=1${env_line} falcon serve --bind http://127.0.0.1:10002"
daemon_user="dev"
daemon_execdir="/home/dev/pub4/MASTER/web"
daemon_timeout="90"
. /etc/rc.d/rc.subr
pexp="ruby34.*falcon.*10002"
rc_bg=YES
rc_reload=NO
rc_cmd \$1
RCEOF
    chmod 555 /etc/rc.d/master
    rcctl enable master
    rcctl start master
    mark_step_completed "master_deployed"
    log INFO "MASTER web UI running on :10002 (relayd :3000 -> :10002)"
  fi
NEW

if content.include?("rcctl enable masterweb")
  content.sub!(old_master_block.strip, new_master_block.strip)
  puts "2. replaced masterweb -> master rc.d with API key injection"
else
  puts "2. masterweb block not found (may already be updated)"
end

# Fix 3: Replace the stale CLI service rc.d for SERVICES entries
old_svc_rcd = <<~'OLD'
    # Create rc.d script for CLI service
    cat > /etc/rc.d/$svc_name <<EOF
#!/bin/ksh
# rc.d for $svc_name (rc.d(8))
daemon_user="dev"
. /etc/rc.d/rc.subr
rc_start() {
  cd /home/dev/pub || return 1
  export PATH=/home/dev/.gem/ruby/3.4/bin:\$PATH
  export ELEVENLABS_API_KEY=\$(cat /home/dev/.elevenlabs_key 2>/dev/null)
  \${rcexec} "ruby cli.rb >> /var/log/${svc_name}.log 2>&1 &"
}
rc_stop() {
  pkill -f "ruby cli.rb" || true
}
rc_cmd \$1
EOF
OLD

# The SERVICES array has ai:ai.brgen.no:4430 — but MASTER is already deployed above.
# Remove the standalone SERVICES loop since MASTER is the only non-Rails service
# and it's handled by the master rc.d block above.
if content.include?("cd /home/dev/pub || return 1")
  content.sub!(old_svc_rcd.strip, <<~'NEW'.strip)
    # MASTER is deployed above; skip CLI-based rc.d for ai service
    log INFO "Service $svc_name handled by master rc.d"
NEW
  puts "3. replaced stale CLI service rc.d"
end

# Fix 4: Remove ALL_APPS separator from colon to avoid ambiguity
# The script uses ${app_entry[(ws:*:)1]} which splits on * but ALL_APPS uses :
# This is a zsh idiom — leave as-is, it works.

# Fix 5: Update the final status message
content.sub!(
  "Test: 'curl https://brgen.no', 'curl https://ai.brgen.no'.",
  "Test: 'curl http://ai.brgen.no:3000/chat/metrics', 'rcctl check master'."
)
puts "5. updated completion message"

File.write(path, content)
puts "\nopenbsd.sh updated"
