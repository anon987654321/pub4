# frozen_string_literal: true

require "digest"
require "json"
require "open3"

module Deploy
  # One /fix RAILS run rendered the same 214 route/viewport cells three times before its first
  # repair, about fourteen minutes each, over a tree nobody had changed.

  # A sweep is keyed by what decides its outcome: RAILS as committed and as edited, the route
  # inventory, the check's code, its settings and the reachable apps. The same key within TTL
  # hands back the recorded rows. Any edit to RAILS, a repair's included, is a new key.
  # CHECK_BROWSER_DIAGNOSTICS_REPLAY=0 always renders.
  class SweepReplay
    TTL = 6 * 3600
    SETTINGS = %w[CHECK_BROWSER_DIAGNOSTICS_SETTLE_MS CHECK_PIXEL_BASELINE_STRICT CHECK_PIXEL_DIFF_MAX_RATIO].freeze

    def self.enabled?(env = ENV) = env["CHECK_BROWSER_DIAGNOSTICS_REPLAY"] != "0"

    def initialize(base:)
      @base = base
    end

    # The inputs a sweep's verdicts depend on, in repository root `root`.
    def self.inputs(root:, check_code:, live_ids:)
      git = ->(*args) { Open3.capture2e("git", "-C", root, *args).first }
      inventory = File.join(root, "MASTER", "checks", "data", "geometry_surfaces.yml")

      [git.("rev-parse", "HEAD:RAILS"), git.("diff", "HEAD", "--", "RAILS"),
       git.("ls-files", "--others", "--exclude-standard", "--", "RAILS"),
       File.read(inventory), File.read(check_code), SETTINGS.map { |name| ENV[name].to_s }, live_ids.sort]
    end

    def key(inputs) = Digest::SHA256.hexdigest(inputs.flatten.join("\0"))

    def remember(key:, manifest:)
      File.write(index(key), JSON.generate("key" => key, "manifest" => manifest))
    rescue SystemCallError => e
      warn "browser0: replay index not written, the next sweep renders: #{e.message}"
    end

    # The recorded rows for this key, or nil when there are none, they are stale or replay is off.
    def rows(key)
      entry = recorded(key)
      entry && JSON.parse(File.read(entry.fetch("manifest"))).fetch("results")
    rescue JSON::ParserError, KeyError, SystemCallError => e
      warn "browser0: recorded sweep unreadable, rendering: #{e.message}"
      nil
    end

    def recorded_at(key) = File.mtime(index(key))

    private

    def index(key) = File.join(@base, "replay-#{key[0, 24]}.json")

    def recorded(key)
      path = index(key)
      return unless self.class.enabled? && File.file?(path) && Time.now - File.mtime(path) < TTL

      entry = JSON.parse(File.read(path))
      entry if entry["key"] == key && File.file?(entry["manifest"].to_s)
    end
  end
end
