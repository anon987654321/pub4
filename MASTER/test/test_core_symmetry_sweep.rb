# frozen_string_literal: true

require "minitest/autorun"
module Master; module Core; module Design; end; end; end

require_relative "../lib/core/design/grammar"
require_relative "../lib/core/design/symmetry_sweep"

class TestSymmetrySweep < Minitest::Test
  def setup
    @sweep = Master::Core::Design::SymmetrySweep.new
  end

  def test_detects_bad_spacing
    # Write a temporary file with bad spacing
    File.write("bad_spacing.css", "div { margin: 7px; }")
    violations = @sweep.sweep(["bad_spacing.css"])
    assert violations.any? { |v| v[:type] == :spacing }
    File.delete("bad_spacing.css")
  end

  def test_accepts_canonical_spacing
    File.write("good_spacing.css", "div { margin: 8px; }")
    violations = @sweep.sweep(["good_spacing.css"])
    assert_empty violations.select { |v| v[:type] == :spacing }
    File.delete("good_spacing.css")
  end
end
