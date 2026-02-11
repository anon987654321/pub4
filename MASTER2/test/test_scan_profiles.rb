# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/master"

class TestScanProfiles < Minitest::Test
  def test_scan_profiles_constant_exists
    assert defined?(MASTER::Engine::SCAN_PROFILES), "SCAN_PROFILES constant should exist"
  end

  def test_scan_profiles_has_three_levels
    assert_equal 3, MASTER::Engine::SCAN_PROFILES.size
    assert MASTER::Engine::SCAN_PROFILES.key?(:quick)
    assert MASTER::Engine::SCAN_PROFILES.key?(:standard)
    assert MASTER::Engine::SCAN_PROFILES.key?(:full)
  end

  def test_scan_profile_quick_has_high_priority
    quick = MASTER::Engine::SCAN_PROFILES[:quick]
    assert_equal 9, quick[:min_priority]
  end

  def test_scan_profile_standard_has_medium_priority
    standard = MASTER::Engine::SCAN_PROFILES[:standard]
    assert_equal 7, standard[:min_priority]
  end

  def test_scan_profile_full_has_no_filter
    full = MASTER::Engine::SCAN_PROFILES[:full]
    assert_equal 0, full[:min_priority]
  end

  def test_scan_accepts_profile_parameter
    # Create a temp test file
    require "tempfile"
    
    Tempfile.create(['test', '.rb']) do |f|
      f.write("# Simple test file\ndef hello\n  puts 'world'\nend\n")
      f.flush
      
      result = MASTER::Engine.scan(f.path, profile: :quick, silent: true)
      assert result.ok?, "Scan with profile should succeed"
    end
  end

  def test_axioms_have_priority_field
    axioms_file = File.join(MASTER::Paths.data, 'axioms.yml')
    assert File.exist?(axioms_file), "axioms.yml should exist"
    
    axioms = YAML.load_file(axioms_file)
    
    # Check that at least some axioms have priority
    with_priority = axioms.select { |a| a['priority'] || a[:priority] }
    assert with_priority.size > 0, "At least some axioms should have priority field"
  end
end
