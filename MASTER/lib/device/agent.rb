# frozen_string_literal: true

require "fileutils"
require "json"
require "securerandom"
require "socket"

module Master
  module Device
    # The long-lived local companion on an Android/Termux host. It does not
    # become the Android owner by assumption: local ownership is an explicit
    # pairing action, and personal memory stays under that subject's workspace.
    #
    # The agent owns cadence, not intelligence. Cognition persists perception;
    # StandingOrders persists objectives. This class merely keeps both alive
    # after the interactive face is closed, with one bounded tick per interval.
    class Agent
      VERSION = 1
      STATE_PATH = ".master/device_agent.json"
      TICK_SECONDS = 60
      ERROR_BACKOFF_SECONDS = 300

      class << self
        extend Master::Io::AtomicWrite
        def start!(root:, bus:, cognition:, standing:)
          return if !Device.android?
          return if ENV["MASTER_DEVICE_AGENT"] == "0"
          return @thread if @thread&.alive?

          agent = new(root:, bus:, cognition:, standing:)
          @stop = false
          @thread = Thread.new { agent.run_forever }
          @thread.report_on_exception = false
        end

        def stop!
          @stop = true
          @thread&.kill
          @thread = nil
        end

        def owner_subject(root: Master::ROOT)
          state(root)["owner_subject"].to_s
        rescue StandardError
          ""
        end

        def paired?(root: Master::ROOT) = !owner_subject(root:).empty?

        # Explicit local-owner consent. The caller is physically running MASTER
        # on the phone; Pairing mints the same scoped personal identity used by
        # remote channels, but the bearer token is never printed.
        def claim_owner!(root:, label: nil)
          existing = owner_subject(root:)
          raise "device already paired; release the current owner before pairing again" unless existing.empty?

          issued = Ground::Pairing.issue(root:, label: label.to_s.empty? ? "local-owner" : label)
          result = Ground::Pairing.redeem(issued[:code], root:)
          raise "local pairing failed" unless result

          Ground::Pairing.apply_token!(result[:token], root:)
          Ground::PersonalWorkspace.append_memory(
            root:, subject: result[:subject], key: "owner_label", body: result[:label], type: "user",
          )
          save_state(root, {
            "owner_subject" => result[:subject],
            "owner_label" => result[:label],
            "paired_at" => Time.now.utc.iso8601,
          })
          result
        end

        def release_owner!(root:)
          subject = owner_subject(root:)
          raise "device is not paired" if subject.empty?

          Ground::Pairing.revoke(subject, root:)
          path = File.join(root, STATE_PATH)
          current = state(root)
          current.delete("owner_subject")
          current.delete("owner_label")
          current.delete("paired_at")
          write_atomic(path, JSON.pretty_generate(current) + "\n", mode: 0o600)
          Fiber[:master_paired] = nil
          Fiber[:master_pair_subject] = nil
          subject
        end

        def status(root: Master::ROOT)
          row = state(root)
          {
            device_id: row["device_id"].to_s,
            owner_subject: row["owner_subject"].to_s,
            owner_label: row["owner_label"].to_s,
            paired: !row["owner_subject"].to_s.empty?,
            started_at: row["started_at"],
            last_tick_at: row["last_tick_at"],
            last_error: row["last_error"],
          }
        end

        private

        def state(root)
          path = File.join(root, STATE_PATH)
          return {} unless File.file?(path)

          JSON.parse(File.read(path, encoding: "UTF-8"))
        rescue JSON::ParserError => e
          Master::Ground::Swallow.log(e, context: "device_agent.state")
          {}
        end

        def save_state(root, changes)
          path = File.join(root, STATE_PATH)
          FileUtils.mkdir_p(File.dirname(path))
          current = state(root)
          payload = current.merge(changes)
          payload["version"] = VERSION
          payload["device_id"] ||= "#{Socket.gethostname}-#{SecureRandom.hex(8)}"
          write_atomic(path, JSON.pretty_generate(payload) + "\n", mode: 0o600)
          payload
        end
      end

      def initialize(root:, bus:, cognition:, standing:, clock: -> { Time.now.to_i }, sleeper: ->(s) { sleep s })
        @root = root
        @bus = bus
        @cognition = cognition
        @standing = standing
        @clock = clock
        @sleeper = sleeper
        @stop = false
        @state = self.class.send(:state, root)
        self.class.send(:save_state, root, "started_at" => Time.now.utc.iso8601) unless @state["started_at"]
      end

      def stop!
        @stop = true
      end

      def run_forever
        loop do
          break if @stop || self.class.instance_variable_get(:@stop)

          tick!
          @sleeper.call(next_sleep)
        rescue StandardError => e
          record_error(e)
          @sleeper.call(ERROR_BACKOFF_SECONDS)
        end
        emit("device_agent:stop")
      end

      def tick!
        @cognition&.tick!
        owner = self.class.owner_subject(root: @root)
        results = owner.empty? ? [] : Array(@standing&.run_due!(owner:))
        now = Time.now.utc.iso8601
        self.class.send(:save_state, @root, "last_tick_at" => now, "last_error" => nil)
        emit("device_agent:tick", paired: !owner.empty?, orders: results.size, at: now)
        results
      end

      private

      def next_sleep
        value = Integer(ENV.fetch("MASTER_DEVICE_TICK_SECONDS", TICK_SECONDS))
        [value, 5].max
      rescue ArgumentError
        TICK_SECONDS
      end

      def record_error(error)
        emit("device_agent:error", error: "#{error.class}: #{error.message}")
        self.class.send(:save_state, @root, "last_error" => "#{error.class}: #{error.message}"[0, 300],
                        "last_error_at" => Time.now.utc.iso8601)
      end

      def emit(event, **fields)
        @bus&.publish(event, **fields)
      rescue StandardError
        nil
      end
    end
  end
end
