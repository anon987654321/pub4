# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

class TestFixScanPhase < Minitest::Test
  FakeScanner = Struct.new(:result, :full, keyword_init: true) do
    def scan(path, depth:)
      raise "unexpected depth" unless depth == :deep
      result
    end

    def full_semantic!
      self.full = true
    end

    def semantic_full? = full == true
  end

  def test_scan_phase_owns_scan_boundary
    Dir.mktmpdir do |root|
      scanner = FakeScanner.new(result: Master::Result.ok([{ rule: "X" }]), full: false)
      events = []
      bus = Object.new
      bus.define_singleton_method(:publish) { |event, **payload| events << [event, payload] }
      phase = Master::Fix::ScanPhase.new(scanner:, root:, bus:)

      result = phase.call(File.join(root, "example.rb"))

      assert result.ok?
      assert_equal "scan", events.fetch(0).first
      assert_equal "example.rb", events.fetch(0).last.fetch(:file)
    end
  end

  def test_full_semantic_is_owned_by_scan_phase
    scanner = FakeScanner.new(result: Master::Result.ok([]), full: false)
    phase = Master::Fix::ScanPhase.new(scanner:, root: Dir.pwd)

    refute phase.semantic_full?
    phase.full_semantic!
    assert phase.semantic_full?
  end
end
