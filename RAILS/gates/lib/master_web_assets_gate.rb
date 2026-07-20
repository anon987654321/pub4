# frozen_string_literal: true

require "json"
require_relative "../../design_tokens"
require_relative "../../../OPENBSD/lib/gate_result"

module Deploy
  class MasterWebAssetsGate
    ROOT = File.expand_path("../../..", __dir__)
    FACE_CSS = File.join(ROOT, "MASTER", "web", "public", "face.css")
    WEB_ROOT = File.join(ROOT, "MASTER", "web")
    ASSETS_DIR = File.join(WEB_ROOT, "public", "assets")
    MANIFEST = File.join(ASSETS_DIR, ".manifest.json")
    REQUIRED = %w[face.css face.js face.runtime.js chat.js three.face.module.js].freeze
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
        result.fail("missing #{MANIFEST} — run: cd MASTER/web && RAILS_ENV=production bundle exec rails assets:precompile")
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
        result.fail("#{relative_path} must run master_web_assets_gate") unless content.include?("master_web_assets_gate.rb")

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
