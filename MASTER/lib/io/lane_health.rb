# frozen_string_literal: true

require "net/http"
require "uri"
require "yaml"
require_relative "../gap"
require_relative "lane_quota"
require_relative "lane_silence"
require_relative "process_spawn"

module Master
  module Io
    # MASTER's model layer answers when any lane can. Remote lanes die of quota,
    # network or an expired login (LaneQuota knows when each is back); the last
    # lane of every tier is a local Ollama model that needs neither. This
    # module is the part that keeps that lane honest and says so when it is not:
    #
    #   ensure_ollama  starts `ollama serve` once when the daemon is down
    #   online_via     the first lane that is not dead, or nil
    #   offline        the typed answer when no lane is left: the Offline error
    #                  carries one line naming each lane's state and reset time
    #
    # Callers treat Offline as "no model work this pass": it is a StandardError,
    # so every `rescue StandardError` that already guards a model call skips the
    # model step and the mechanical fixes go on.
    module LaneHealth
      extend self

      # `gap` says when a lane comes back and what finding out costs.
      class Offline < StandardError
        attr_reader :gap

        def initialize(message = nil, gap: nil)
          super(message)
          @gap = gap
        end
      end

      Ollama = Data.define(:state, :message)

      START_WAIT_S = 10
      PROBE_TIMEOUT_S = 2
      RETRY_AFTER_FAILED_START_S = 60
      DEFAULT_BASE = "http://localhost:11434"

      @mutex = Mutex.new
      @failed_at = nil
      @clock = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }

      attr_writer :clock

      def ollama_base
        url = ENV["OLLAMA_BASE_URL"].to_s.strip
        url.empty? ? DEFAULT_BASE : url.chomp("/").delete_suffix("/v1")
      end

      def ollama_up?(base = ollama_base)
        uri = URI.join("#{base}/", "api/tags")
        http = Net::HTTP.new(uri.host, uri.port)
        http.open_timeout = http.read_timeout = PROBE_TIMEOUT_S
        http.start { |session| session.get(uri.path).is_a?(Net::HTTPSuccess) }
      rescue StandardError
        false
      end

      # Starts `ollama serve` detached when a local daemon is down, once per
      # minute at most, and reports what happened. A remote daemon is never started.
      def ensure_ollama(base: ollama_base, up: method(:ollama_up?), spawn: method(:spawn_ollama), binary: "ollama")
        return Ollama.new(:off, "ollama switched off (MASTER_NO_OLLAMA=1)") if ENV["MASTER_NO_OLLAMA"] == "1"
        return Ollama.new(:up, "ollama is up at #{base}") if up.call(base)
        return Ollama.new(:failed, "ollama is down at #{base} and is not local, start it there") unless local?(base)

        @mutex.synchronize { attempt_start(base, up:, spawn:, binary:) }
      end

      # The first catalogue model on a lane, for a probe of that lane.
      def model_for_lane(lane)
        cfg = LaneSelection.config
        models = cfg.fetch("models", {}).values.flatten.filter_map do |row|
          row["id"] if row.is_a?(Hash)
        end
        models.concat(cfg.fetch("model_defs", {}).values.filter_map { |row| row["id"] if row.is_a?(Hash) })
        cfg.fetch("cli_lanes", {}).each do |name, spec|
          models.concat(Array(spec["models"]).map { |model| "#{name}:#{model}" })
        end
        models.uniq.find do |model|
          LaneQuota.lane_of(model) == lane || model.start_with?(lane.to_s)
        end
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "LaneHealth.model_for_lane", lane:)
        nil
      end

      def online_via(models, refuses: ->(model) { dead?(model) })
        Array(models).find { |model| !refuses.call(model) }
      end

      def dead?(model)
        LaneSilence.refuses?(model)
      rescue NameError
        Master::Io::LaneQuota.dead?(model)
      end

      # "claude-cli: quota spent, back in 2h3m (..); ollama: live" for each lane once.
      def states(models, refuses: ->(model) { dead?(model) })
        lanes = Array(models).uniq { |model| LaneQuota.report_for(model) || LaneQuota.lane_of(model) }
        lanes.map do |model|
          lane = LaneQuota.lane_of(model)
          LaneQuota.report_for(model) || (refuses.call(model) ? "#{lane}: silent (no answer lately)" : "#{lane}: live")
        end
      end

      # One line for status and logs.
      def line(models, refuses: ->(model) { dead?(model) })
        via = online_via(models, refuses:)
        return "online: yes via #{via}" if via

        "online: NO (all lanes dead) #{states(models, refuses:).join("; ")}"
      end

      def offline_error(models, refuses: ->(model) { dead?(model) })
        gap = gap_for(models)
        Offline.new("offline: no lane answers; #{states(models, refuses:).join("; ")}. #{gap.clause}", gap:)
      end

      # The soonest a lane revives by its own clock, probed for in minutes; when
      # no lane has a clock (all dead by hand or silent) only the operator revives one.
      def gap_for(models)
        waits = Array(models).filter_map { |model| LaneQuota.revival_in(model) }
        return Master::Gap.new(horizon: waits.min, cost_to_check: :minutes) if waits.any?

        Master::Gap.new(horizon: :operator, cost_to_check: :operator)
      end

      def local?(base) = URI(base).host.to_s.match?(/\A(?:localhost|127\.\d+\.\d+\.\d+|\[?::1\]?)\z/)

      # An Ollama model that runs on this machine: no network, no quota.
      def local_model?(model)
        id = model.to_s
        id.start_with?("ollama:") && !id.end_with?(":cloud", "-cloud")
      end

      private

      def attempt_start(base, up:, spawn:, binary:)
        return Ollama.new(:failed, "ollama is down at #{base}; start failed #{(@clock.call - @failed_at).to_i}s ago, run `ollama serve`") if recently_failed?
        return Ollama.new(:failed, "ollama is down at #{base} and `#{binary}` is not installed") unless on_path?(binary)

        spawn.call(binary)
        deadline = @clock.call + START_WAIT_S
        until @clock.call >= deadline
          return Ollama.new(:started, "started `ollama serve` for #{base}") if up.call(base)

          sleep 0.5
        end
        @failed_at = @clock.call
        Ollama.new(:failed, "started `ollama serve` but #{base} did not answer in #{START_WAIT_S}s; run it by hand")
      end

      def recently_failed? = @failed_at && @clock.call - @failed_at < RETRY_AFTER_FAILED_START_S

      def spawn_ollama(binary)
        pid = Process.spawn(binary, "serve", **ProcessSpawn.options(out: File::NULL, err: File::NULL, pgroup: true))
        Process.detach(pid)
      end

      def on_path?(binary)
        ENV["PATH"].to_s.split(File::PATH_SEPARATOR).any? { |dir| File.executable?(File.join(dir, binary)) && File.file?(File.join(dir, binary)) }
      end
    end
  end
end
