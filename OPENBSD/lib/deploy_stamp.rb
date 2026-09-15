# frozen_string_literal: true

require "json"

module Deploy
  # What `bin/vps-deploy` wrote after its last run, and whether a running
  # process is the build that run deployed.
  #
  # master reports the commit it booted as /health `deploy.git_sha`, and the
  # deploy records the commit it pulled in `last_deploy_master.json`. Each is
  # correct about itself. Both can be correct while disagreeing: a checkout
  # pulled after the deploy, then a reboot or a hand restart, boots code no
  # deploy ever ran, and every other check still passes. The comparison is the
  # only place that state becomes a fact.
  module DeployStamp
    DIR = "/var/db/pub4"

    module_function

    # The stamp's sha, or nil for an absent or unreadable stamp.
    def sha(app, dir: DIR)
      path = File.join(dir, "last_deploy_#{app}.json")
      return nil unless File.readable?(path)

      value = JSON.parse(File.read(path))["sha"].to_s
      value.empty? ? nil : value
    rescue JSON::ParserError
      nil
    end

    # nil when the booted build is the stamped one, a failure line when not.
    # Short SHAs differ in length between `git rev-parse --short` runs as the
    # object count grows, so one naming a prefix of the other is the same commit.
    def booted_mismatch(app:, booted:, stamped:)
      booted = booted.to_s
      return "#{app} health: no deploy.git_sha — the booted build is unknown" if booted.empty?
      return nil if stamped.nil? || booted.start_with?(stamped) || stamped.start_with?(booted)

      "#{app} health: booted #{booted} but last deploy stamped #{stamped} — " \
        "this process runs code no deploy ran; `bin/vps-deploy #{app}` makes them one"
    end
  end
end
