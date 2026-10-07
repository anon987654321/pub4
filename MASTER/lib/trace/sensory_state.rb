# frozen_string_literal: true

require "json"
require "fileutils"
require "monitor"
require "time"

module Master
  module Trace
    # One small, redacted state projection for the whole machine.
    #
    # EventBus remains the source of events; SensoryState is only the current
    # state projection used by CLI diagnostics and the face. It never stores
    # conversation text, model prompts, tokens, paths, or credentials.
    module SensoryState
      extend MonitorMixin
      module_function
      extend self

      VERSION = 1
      MAX_HISTORY = 32
      PATH = File.join(Master::ROOT, ".master", "sensory_state.json")
      INTERESTING = %w[
        heartbeat:** fix_loop:** stt:** tts:** voice:** model:** gate:**
        scan:** task:** tool:** ui:** web:** system:**
      ].freeze

      @state = {
        version: VERSION,
        interaction: "idle",
        voice: "idle",
        visual: "idle",
        task: "idle",
        system: "ready",
        updated_at: nil,
        history: [],
      }

      def attach!(bus, root: Master::ROOT)
        return unless bus

        @root = root
        INTERESTING.each { |pattern| bus.subscribe(pattern) { |event| observe(event) } }
        write!
        true
      end

      def observe(event)
        name = event[:event].to_s
        changes = transition(name)
        return snapshot if changes.empty?

        synchronize do
          @state.merge!(changes, updated_at: Time.now.utc.iso8601)
          @state[:history] = (@state[:history] + [{ "event" => family(name), "at" => @state[:updated_at] }]).last(MAX_HISTORY)
          write_unlocked!
        end
        snapshot
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "SensoryState.observe")
        snapshot
      end

      def snapshot(root: @root || Master::ROOT)
        path = File.join(root, ".master", "sensory_state.json")
        return synchronize { deep_copy(@state) } unless File.file?(path)

        JSON.parse(File.read(path))
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "SensoryState.snapshot")
        synchronize { deep_copy(@state) }
      end

      def transition(name)
        case name
        when /Astt:startz/ then { interaction: "listening", voice: "listening", visual: "attention" }
        when /Astt:endz/, /Astt:abortz/ then { interaction: "processing", voice: "idle", visual: "working" }
        when /Atts:playback:startz/, /Avoice:speakingz/ then { interaction: "speaking", voice: "speaking", visual: "attention" }
        when /Atts:playback:endz/, /Avoice:idlez/ then { interaction: "idle", voice: "idle", visual: "idle" }
        when /Afix_loop:/ then { interaction: "processing", task: "fixing", visual: "working", system: "maintenance" }
        when /Agate:/, /Ascan:/ then { interaction: "processing", task: "checking", visual: "working", system: "checking" }
        when /Aheartbeat:(?:run|mission_wake)/ then { task: "observing", system: "maintenance" }
        when /Aheartbeat:(?:scan_clean|self_test)/ then { task: "idle", visual: "success", system: "ready" }
        when /Aheartbeat:errorz/ then { task: "idle", visual: "error", system: "degraded" }
        when /Amodel:/ then { interaction: "processing", visual: "working", system: "thinking" }
        when /Atool:completez/, /Atask:completez/ then { task: "idle", visual: "success" }
        when /Atool:failedz/, /Atask:failedz/ then { task: "idle", visual: "error" }
        when /Aui:awayz/ then { interaction: "sleeping", visual: "idle" }
        when /Aui:returnz/ then { interaction: "idle", visual: "attention" }
        when /Asystem:readyz/ then { system: "ready", visual: "idle" }
        else {}
        end
      end

      def family(name)
        name.split(":", 2).first.to_s
      end

      def write!
        synchronize { write_unlocked! }
      end

      def write_unlocked!
        root = @root || Master::ROOT
        path = File.join(root, ".master", "sensory_state.json")
        FileUtils.mkdir_p(File.dirname(path))
        tmp = "#{path}.tmp.#{$$}.#{Thread.current.object_id}"
        File.write(tmp, JSON.pretty_generate(@state))
        File.rename(tmp, path)
      ensure
        File.delete(tmp) if tmp && File.exist?(tmp)
      end

      def deep_copy(value)
        JSON.parse(JSON.generate(value))
      end
    end
  end
end
