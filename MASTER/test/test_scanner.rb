# frozen_string_literal: true

require_relative "test_helper"

class TestScanner < Minitest::Test
  class FakeBus
    attr_reader :events

    def initialize
      @events = []
    end

    def publish(name, payload = nil, **kwargs)
      @events << [name, payload || kwargs]
    end
  end

  class BoomScanner < Master::Judge::Scan::Scanner
    private

    def scan_one(dir:, path:, depth:, stream:, index: nil)
      raise "boom #{index}"
    end
  end

  def test_scan_reads_file_and_publishes_completion
    Dir.mktmpdir do |dir|
      path = File.join(dir, "sample.rb")
      File.write(path, "puts 'ok'\n")
      bus = FakeBus.new
      scanner = Master::Judge::Scan::Scanner.new(rules: [build_rule], event_bus: bus)

      result = scanner.scan(path)

      assert result.ok?
      assert_empty result.value!
      assert bus.events.any? { |name, payload| name == "scan:file_read" && payload[:path] == path }
      assert bus.events.any? { |name, payload| name == "scan:complete" && payload[:count].zero? }
    end
  end

  def test_scan_dir_surfaces_thread_errors_via_bus
    Dir.mktmpdir do |dir|
      path = File.join(dir, "sample.rb")
      File.write(path, "puts 'ok'\n")
      bus = FakeBus.new
      scanner = BoomScanner.new(rules: [build_rule], event_bus: bus)

      result = scanner.scan_dir(dir)

      assert result.ok?
      file_path, file_result = result.value!.first
      assert_equal path, file_path
      assert file_result.err?
      assert bus.events.any? { |name, payload| name == "scanner:thread_error" && payload[:path] == path }
    end
  end

  private

  def build_rule
    Class.new do
      def check(_code, path:)
        []
      end
    end.new
  end
end
