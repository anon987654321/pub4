# frozen_string_literal: true

module Master
  module Now
    class CLI
      class BackgroundScan
        IDLE_SLEEP_DEFAULT = 60

        def initialize(cli:)
          @cli = cli
          @stop = false
        end

        def request_stop!
          @stop = true
          thread = @cli.instance_variable_get(:@bg_thread)
          thread&.kill
          @cli.instance_variable_set(:@bg_thread, nil)
        end

        def start!
          @cli.instance_variable_set(:@bg_thread, Thread.new do
            boot_scan
            loop do
              break if @stop
              sleep IDLE_SLEEP_DEFAULT
              cycle unless @cli.instance_variable_get(:@user_active)
            end
          rescue StandardError => e
            @cli.bus&.publish("cli:bg_error", error: e.message)
          end)
        end

        def boot_scan
          result = Master::Judge::Scan::SelfScan.new(
            scanner: @cli.scanner, root: @cli.root, event_bus: @cli.bus
          ).call(autofix: true)
          return unless result.is_a?(Master::Result) && result.ok?

          summary = result.value!
          @cli.update_violations(summary.violation_count)
          return if summary.violation_count.zero?
          puts
          puts @cli.renderer.render(summary.line, mode: :dim)
          puts
        rescue StandardError => e
          @cli.bus&.publish("cli:warn", error: e.message)
        end

        def cycle
          lib_dir = File.join(@cli.root, "lib")
          result = @cli.scanner.scan_dir(lib_dir, depth: :deep)
          return unless result.is_a?(Master::Result) && result.ok?
          n = count_violations(result.value!)
          prev = @cli.violations
          return if n == prev
          @cli.update_violations(n)
          $stdout.puts "\nbg: #{n} violation(s)" if n.positive?
          $stdout.flush
        rescue StandardError => e
          @cli.bus&.publish("cli:bg_error", error: e.message)
        end

        private

        def count_violations(pairs)
          pairs.sum do |_file, file_result|
            file_result.is_a?(Master::Result) && file_result.ok? ? file_result.value!.size : 0
          end
        end
      end
    end
  end
end