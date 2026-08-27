# frozen_string_literal: true

require "json"
require_relative "../../../tools/design_tokens"
require_relative "../../../../OPENBSD/lib/gate_result"

module Deploy
  class MasterWebAssetsGate
    ROOT = File.expand_path("../../../..", __dir__)
    FACE_CSS = File.join(ROOT, "MASTER", "web", "public", "face.css")
    WEB_ROOT = File.join(ROOT, "MASTER", "web")
    ASSETS_DIR = File.join(WEB_ROOT, "public", "assets")
    MANIFEST = File.join(ASSETS_DIR, ".manifest.json")
    REQUIRED = %w[face.css face.js face.runtime.js chat.js three.face.module.js].freeze
    # Same two files Pub4::CiGuard uses to recognise vm23. Only there is a missing
    # precompiled manifest a deploy fault rather than an unbuilt checkout.
    DEPLOY_HOST_MARKERS = ["/etc/relayd.conf", "/var/db/pub4_vps"].freeze
    DEPLOY_SCRIPTS = {
      "OPENBSD/OPERATOR.sh" => :start_or_restart,
      "OPENBSD/vps_install_all.sh" => :start_or_restart,
      "OPENBSD/vps_on_vm_install.sh" => :start_or_restart,
      "OPENBSD/vps_console.exp" => :restart,
      "OPENBSD/vps_deploy_master.sh" => :restart,
    }.freeze

    def self.run
      result = GateResult.new

      if (drift = DesignTokens.face_root_drift?(FACE_CSS))
        result.fail(drift)
      end
      if (drift = DesignTokens.scss_anchor_drift?)
        result.fail(drift)
      end

      unless File.file?(MANIFEST)
        # MASTER/web/public/assets is gitignored — precompile writes it, and only
        # where something has run precompile. So its absence means two different
        # things, and this reported the harsher one everywhere: on the deploy host
        # a missing manifest is a real broken deploy, but in a fresh clone or a
        # `MASTER/bin/pub4 worktree` checkout it means nobody has built assets here
        # yet. That made `production` fail on arrival in any new working copy,
        # which is a gate people learn to read past — and this one guards the
        # face's assets.
        #
        # Inconclusive off the host, per the same rule the rendered gates follow:
        # a gate that measured nothing says so rather than picking a verdict.
        # GATE_STRICT_INCONCLUSIVE=1 still turns it into a failure.
        if DEPLOY_HOST_MARKERS.any? { |marker| File.exist?(marker) }
          result.fail("missing #{MANIFEST} — run: cd MASTER/web && RAILS_ENV=production bundle exec rails assets:precompile")
        else
          result.inconclusive!("MASTER/web assets not precompiled in this checkout — " \
                               "gitignored, so nothing to read until `cd MASTER/web && " \
                               "RAILS_ENV=production bundle exec rails assets:precompile` has run here")
        end
      else
        manifest = JSON.parse(File.read(MANIFEST))
        REQUIRED.each do |logical|
          entry = manifest[logical]
          result.fail("manifest missing #{logical}") unless entry
          next unless entry

          digested = entry["digested_path"].to_s
          result.fail("manifest #{logical} has empty digested_path") if digested.empty?
          path = File.join(ASSETS_DIR, digested)
          result.fail("missing digested asset #{digested} for #{logical}") unless File.file?(path)
        end
      end

      DEPLOY_SCRIPTS.each do |relative_path, restart_mode|
        path = File.join(ROOT, relative_path)
        unless File.file?(path)
          result.fail("missing MASTER web deploy script #{relative_path}")
          next
        end

        content = File.read(path)
        result.fail("#{relative_path} must precompile MASTER/web assets") unless content.include?("assets:precompile")
        # Matched on the gate name, not on a script path: the per-gate scripts at
        # the RAILS root were shims, and every caller now names the gate for
        # gates/runner.rb instead.
        runs_gate = content.match?(/gates\/runner\.rb"?\s+master_web_assets/)
        result.fail("#{relative_path} must run the master_web_assets gate") unless runs_gate

        restarts_master = content.include?("rcctl restart master")
        starts_master = content.include?("rcctl start master")
        if restart_mode == :restart
          result.fail("#{relative_path} must restart master after precompile") unless restarts_master
        elsif !restarts_master && !starts_master
          result.fail("#{relative_path} must start or restart master after precompile")
        end
      end

      result
    end
  end
end
