# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "monitor"
require "time"
require_relative "catalog_index"
require_relative "lane_selection"
require_relative "lane_health"
require_relative "lane_state"
require_relative "media_transport"
require_relative "../boot/paths"

module Master
  module Io
    # Image and video generation by availability, the way Io::LaneSelection picks a
    # text model: the lanes data/models.yml `media_lanes` lists per kind, the live
    # ones only (key present, not refused by Io::LaneState), free first
    # and then the cheapest. A reply that says quota, credits or a refused key parks
    # the lane through LaneQuota after one call and the next live lane answers; a
    # timeout silences it for the cool-off. When no lane is left the answer is a
    # typed :offline Err, never a made-up image.
    #
    # Spend is counted in process from each lane's estimate (the provider's own cost
    # when its reply states one) against a per-run budget and a per-call cap; a lane
    # that does not fit is skipped with a line. A content-policy refusal ends the
    # call as a stage failure with the provider's words and is never retried on
    # another lane. Results are written under an operator-owned directory outside
    # the repo, never over an existing file, with a provenance sidecar.
    module MediaLanes
      extend self

      Lane = Data.define(:kind, :provider, :model, :row) do
        def lane = "media-#{provider}"
        def id = "#{lane}:#{model}"
      end
      KINDS = %i[image video].freeze
      EXT = { "image/png" => "png", "image/jpeg" => "jpg", "image/webp" => "webp", "video/mp4" => "mp4" }.freeze
      PER_MILLION = 1_000_000.0
      LOCK = Monitor.new
      @spent = Hash.new(0.0)
      @config = nil
      @catalog = nil

      attr_writer :config, :catalog

      def config = @config || LaneSelection.config.fetch("media_lanes")

      def reset! = LOCK.synchronize { @spent = Hash.new(0.0) }

      def spent(kind) = LOCK.synchronize { @spent[kind.to_sym] }

      def paid? = ENV["MASTER_MEDIA_PAID"] != "0"

      def run_budget(kind)
        override = ENV["MASTER_MEDIA_BUDGET_USD"].to_s.strip
        override.empty? ? Float(config.dig("budget_usd", kind.to_s)) : Float(override)
      end

      def remaining(kind) = run_budget(kind) - spent(kind)

      def call_cap(kind) = [Float(config.dig("call_cap_usd", kind.to_s)), run_budget(kind)].min

      def key_for(provider, env: ENV)
        names = config.dig("providers", provider, "env") || []
        found = names.map { |name| env[name].to_s.strip }.find { |value| !value.empty? }
        found ||= ReplicateClient.load_token.to_s if provider == "replicate" && env.equal?(ENV)
        found.to_s.empty? ? nil : found
      end

      # Every lane the data lists for the kind, then the catalog's image/video
      # models it does not, as OpenRouter lanes. Order here is the tie-break.
      def lanes(kind)
        listed = config.fetch(kind.to_s).map { |row| Lane.new(kind.to_sym, row["provider"], row["model"], row) }
        listed + catalog_lanes(kind.to_sym, listed.map(&:id))
      end

      def configured?(kind, env: ENV) = lanes(kind).any? { |lane| key_for(lane.provider, env:) }

      # The lanes that can be asked now, in selection order, and why the rest cannot.
      def evaluate(kind, prompt = "", env: ENV, seconds: nil, skip: [])
        live = []
        out = []
        lanes(kind).each do |lane|
          reason = unavailable(lane, env, skip)
          cost = estimate(lane, prompt, seconds:)
          reason ||= over(kind, cost)
          reason ? out << [lane, reason] : live << [lane, cost]
        end
        [live.each_with_index.sort_by { |(lane, cost), index| [free?(lane) ? 0 : 1, cost, index] }.map(&:first), out]
      end

      def first_live(kind, env: ENV) = evaluate(kind, env:).first.first&.first

      def generate(kind, prompt, env: ENV, dir: nil, reuse: false, opts: {})
        started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        cache_status = reuse ? "miss" : "off"
        kind = kind.to_sym
        return fail_validation("unknown media kind #{kind.inspect}") unless KINDS.include?(kind)
        return fail_validation("empty prompt") if prompt.to_s.strip.empty?

        dir = output_dir(kind, dir)
        digest = Digest::SHA256.hexdigest(prompt)
        cached = reuse && cached_take(dir, digest)
        if cached
          cache_status = "hit"
          return announce_cached(kind, cached)
        end

        attempt(kind, prompt, digest, dir, env, opts)
      rescue ArgumentError => e
        fail_validation(e.message)
      ensure
        if started_at && (!defined?(kind) || kind.nil? || KINDS.include?(kind))
          elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
          say("latency media=#{kind || "unknown"} reuse=#{cache_status || "off"} elapsed_ms=#{elapsed_ms}")
        end
      end

      private

      def attempt(kind, prompt, digest, dir, env, opts)
        tried = []
        loop do
          live, skipped = evaluate(kind, prompt, env:, seconds: opts[:seconds], skip: tried)
          skipped.each { |lane, why| say("skip #{lane.id}: #{why}") unless tried.any? || why.start_with?("no key") }
          lane, cost = live.first
          return stuck(kind, skipped, tried) unless lane

          tried << lane.id
          begin
            artifact = MediaTransport.call(lane, prompt, key: key_for(lane.provider, env:), cfg: config, opts:)
            return deliver(lane, artifact, artifact.cost || cost, prompt, digest, dir)
          rescue MediaTransport::Refused => e
            say("#{lane.id} refused the prompt; not retried elsewhere")
            return Master::Result.err("#{lane.id} refused: #{e.message}", category: :policy, context: { lane: lane.id, refusal: e.message })
          rescue StandardError => e
            fail_over(lane, e)
          end
        end
      end

      # Quota, credits and refused keys park the lane (one reply is enough); a
      # timeout silences it; an unreadable reply only skips it for this call.
      def fail_over(lane, error)
        said = error.message
        if error.is_a?(MediaTransport::TimedOut)
          LaneSilence.silence(lane.lane, reason: said)
          say("#{lane.id} silent: #{said}")
        elsif (deadline = LaneQuota.note(lane.id, said))
          say("#{lane.id} parked until #{Time.at(deadline).utc.strftime("%F %H:%M")}Z: #{said[0, 120]}")
        else
          say("#{lane.id} failed (#{error.class.name.split("::").last}): #{said[0, 160]}")
        end
      end

      def stuck(kind, skipped, tried)
        reasons = skipped.map { |lane, why| "#{lane.id}: #{why}" }
        if skipped.any? { |_lane, why| why.match?(/\A(?:estimate|paid)/) } && tried.empty?
          return Master::Result.err("no #{kind} lane fits the budget; #{reasons.join("; ")}", category: :budget)
        end

        ids = lanes(kind).map(&:id)
        say("offline: no #{kind} lane answers")
        Master::Result.err("offline: no #{kind} lane answers; #{reasons.first(8).join("; ")}", category: :offline, gap: LaneHealth.gap_for(ids))
      end

      def unavailable(lane, env, skip)
        return "already tried" if skip.include?(lane.id)
        return "no key (#{config.dig("providers", lane.provider, "env").join("/")})" unless key_for(lane.provider, env:)
        return "paid lanes off (MASTER_MEDIA_PAID=0)" if !paid? && !free?(lane)
        LaneState.verdict(lane.id).reason
      end

      def over(kind, cost)
        return "estimate $#{format("%.3f", cost)} over the call cap $#{format("%.2f", call_cap(kind))}" if cost > call_cap(kind)

        "estimate $#{format("%.3f", cost)} over the $#{format("%.2f", remaining(kind))} left of the run budget" if cost > remaining(kind)
      end

      def free?(lane) = lane.row["free"] == true || lane.model.end_with?(":free")

      # Catalog price first (tokens at the row's price_id), else the data's flat figure.
      def estimate(lane, prompt, seconds: nil)
        row = lane.row
        return Float(row["usd_per_second"]) * (seconds || config["video_seconds"]) if row["usd_per_second"]
        return 0.0 if free?(lane)

        price = catalog[row["price_id"] || (lane.provider == "openrouter" ? lane.model : nil)]
        return Float(row.fetch("usd_per_call")) unless price

        tokens = row["image_tokens"] || config["image_tokens"]
        prompt_tokens = (prompt.to_s.length / 3.0).ceil
        prompt_tokens * price["prompt"] + tokens * (price["image_output"] || price["completion"])
      end

      def catalog_lanes(kind, known)
        merge = config.fetch("catalog_merge")
        rows = catalog.select { |id, price| price["outputs"].include?(kind.to_s) && !known.include?("media-openrouter:#{id}") && price["prompt"] * PER_MILLION <= merge["max_prompt_usd_per_m"] && price["prompt"].positive? }
        rows.keys.first(merge["max_models"]).map { |id| Lane.new(kind, "openrouter", id, { "usd_per_call" => 0.1 }) }
      end

      # id => {prompt, completion, image_output, outputs}, USD per token, from the
      # refreshed OpenRouter catalog; empty when there is none.
      def catalog
        return @catalog if @catalog

        db = CatalogIndex::DEFAULT_DB
        stamp = File.file?(db) ? File.mtime(db).to_f : 0
        @memo = [stamp, read_catalog(db)] unless @memo && @memo[0] == stamp
        @memo[1]
      end

      def read_catalog(db)
        return {} unless File.file?(db)

        handle = SQLite3::Database.new(db, readonly: true)
        handle.execute("SELECT id, output_modalities, raw_json FROM provider_models WHERE source = 'openrouter'").filter_map do |id, outputs, raw|
          pricing = JSON.parse(raw)["pricing"] || {}
          [id, { "outputs" => outputs.to_s.split(","), "prompt" => pricing["prompt"].to_f, "completion" => pricing["completion"].to_f, "image_output" => pricing["image_output"]&.to_f }]
        end.to_h
      rescue StandardError
        {}
      ensure
        handle&.close
      end

      def deliver(lane, artifact, cost, prompt, digest, dir)
        LOCK.synchronize { @spent[lane.kind] += cost }
        base = "#{lane.kind}-#{Time.now.utc.strftime("%Y%m%dT%H%M%SZ")}-#{digest[0, 8]}"
        provenance = { "kind" => lane.kind.to_s, "lane" => lane.id, "provider" => lane.provider, "model" => lane.model, "prompt_sha256" => digest,
                       "time" => Time.now.utc.iso8601, "cost_estimate_usd" => cost.round(4), "cost_source" => artifact.cost ? "provider" : "estimate",
                       "bytes" => artifact.bytes.bytesize, "sha256" => Digest::SHA256.hexdigest(artifact.bytes), "cached" => false }
        path = write_take(dir, base, EXT.fetch(artifact.mime), artifact.bytes, provenance)
        say("#{lane.kind} via #{lane.id} est $#{format("%.3f", cost)} cached=no run $#{format("%.2f", spent(lane.kind))}/#{format("%.2f", run_budget(lane.kind))} -> #{path}")
        Master::Result.ok(provenance.merge("path" => path, "mime" => artifact.mime))
      end

      def announce_cached(kind, take)
        say("#{kind} via #{take["lane"]} est $0.000 cached=yes -> #{take["path"]}")
        Master::Result.ok(take.merge("cached" => true))
      end

      def cached_take(dir, digest)
        Dir.glob(File.join(dir, "*-#{digest[0, 8]}*.json")).sort.reverse_each do |sidecar|
          take = JSON.parse(File.read(sidecar))
          next unless take["prompt_sha256"] == digest

          path = sidecar.delete_suffix(".json")
          next unless File.file?(path)

          expected = take["sha256"].to_s
          next unless expected.match?(/\A[0-9a-f]{64}\z/)
          next unless Digest::SHA256.file(path).hexdigest == expected

          return take.merge("path" => path)
        rescue JSON::ParserError, SystemCallError, IOError
          next
        end
        nil
      end

      # Media bytes and sidecar are linked into place under a name nobody holds:
      # link(2) fails on an existing name, so a render is never replaced.
      def write_take(dir, base, ext, bytes, provenance)
        FileUtils.mkdir_p(dir)
        suffix = nil
        loop do
          path = File.join(dir, "#{base}#{suffix}.#{ext}")
          return link_new(path, bytes, provenance) unless File.exist?(path) || File.exist?("#{path}.json")

          suffix = suffix.to_i.succ.then { |n| "-#{n}" }
          raise "no free name for #{base} in #{dir}" if suffix == "-100"
        end
      rescue Errno::EEXIST
        retry
      end

      def link_new(path, bytes, provenance)
        link_atomic(path, bytes)
        link_atomic("#{path}.json", JSON.pretty_generate(provenance.merge("file" => File.basename(path))))
        path
      end

      def link_atomic(path, content)
        temp = "#{path}.#{Process.pid}.part"
        File.open(temp, "wb", 0o644) { |file| file.write(content); file.fsync }
        File.link(temp, path)
      ensure
        FileUtils.rm_f(temp) if temp
      end

      # Operator-owned and outside the repo: renders are irreplaceable.
      def output_dir(kind, dir)
        root = File.expand_path(dir || ENV["MASTER_MEDIA_DIR"] || MasterPaths.state("media"))
        repo = File.expand_path(MasterPaths.repo)
        raise ArgumentError, "media output dir #{root} is inside the repo #{repo}" if root == repo || root.start_with?("#{repo}/")

        File.join(root, kind.to_s)
      end

      def fail_validation(message) = Master::Result.err(message, category: :validation)

      def say(text) = Master::Trace::Dmesg.status("media0", text)
    end
  end
end
