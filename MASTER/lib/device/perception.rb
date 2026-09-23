# frozen_string_literal: true

module Master
  module Device
    class Perception
      DEFAULT_INTERVAL = 15
      SENSOR_INTERVAL = 3
      MAX_BACKOFF = 120
      SENSOR_NAMES = {
        "accelerometer" => /accelerometer/i,
        "gyroscope" => /gyroscope|gyro/i,
        "magnetometer" => /magnetic.*field|magnetometer/i,
        "light" => /light/i,
        "proximity" => /proximity/i,
      }.freeze

      def initialize(bus:, interval: DEFAULT_INTERVAL)
        @bus = bus
        @interval = [Integer(interval), 1].max
        @stop = false
        @thread = nil
        @sensor_names = nil
        @backoff = 0
      end

      def start!
        return @thread if running?
        return unless Device.android? && Device.termux?

        @stop = false
        @thread = Thread.new { run }
        @thread.report_on_exception = false
        @thread
      end

      def stop!
        @stop = true
        @thread&.kill
        @thread = nil
      end

      def running?
        @thread&.alive? == true
      end

      def sample_once
        return {} unless Device.android? && Device.termux?

        sample_battery
        sample_network
        sample_sensors
      rescue StandardError => e
        publish("device:error", error: e.message)
        {}
      end

      private

      def run
        publish("device:ready", platform: "android", termux_api: true)
        while !@stop
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          sample_once
          sleep_for(started)
        end
      rescue StandardError => e
        publish("device:error", error: e.message)
      ensure
        @thread = nil if Thread.current == @thread
      end

      def sleep_for(started)
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        remaining = [@interval - elapsed, 0.25].max
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + remaining
        sleep(0.25) while !@stop && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
      end

      def sample_battery
        data = Device.battery
        publish("device:battery", normalize(data))
        @backoff = 0
      rescue StandardError => e
        publish("device:battery:error", error: e.message)
        backoff!
      end

      def sample_network
        data = Device.wifi_info
        publish("device:network", normalize(data))
      rescue StandardError => e
        publish("device:network:error", error: e.message)
      end

      def sample_sensors
        data = Device.sensors
        @sensor_names ||= discover_sensor_names(data)
        publish("device:sensors", sensors: normalize(data), names: @sensor_names)
        SENSOR_NAMES.each do |kind, pattern|
          name = @sensor_names.find { |candidate| pattern.match?(candidate) }
          next unless name
          publish("device:#{kind}", normalize(Device.sensor_once(name:)))
        rescue StandardError => e
          publish("device:#{kind}:error", error: e.message)
        end
      rescue StandardError => e
        publish("device:sensors:error", error: e.message)
        backoff!
      end

      def discover_sensor_names(data)
        case data
        when Array then data.map(&:to_s)
        when Hash then data.keys.map(&:to_s)
        else data.to_s.lines.map(&:strip).reject(&:empty?)
        end
      end

      def normalize(data)
        data.is_a?(Hash) ? data : { value: data }
      end

      def publish(event, payload = {})
        @bus&.publish(event, payload.merge(source: "android"))
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "device.perception.publish", event:)
      end

      def backoff!
        @backoff = @backoff.zero? ? @interval : [@backoff * 2, MAX_BACKOFF].min
        @interval = @backoff
      end
    end
  end
end
