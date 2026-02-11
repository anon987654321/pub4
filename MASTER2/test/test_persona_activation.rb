# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/master"

class TestPersonaActivation < Minitest::Test
  def teardown
    # Clean up after each test
    MASTER::Personas.deactivate if defined?(MASTER::Personas.deactivate)
  end

  def test_personas_class_has_activate_method
    assert_respond_to MASTER::Personas, :activate
  end

  def test_personas_class_has_deactivate_method
    assert_respond_to MASTER::Personas, :deactivate
  end

  def test_personas_class_has_active_method
    assert_respond_to MASTER::Personas, :active
  end

  def test_activate_valid_persona
    skip "Requires personas.yml to be populated" unless File.exist?(File.join(MASTER::Paths.data, 'personas.yml'))
    
    personas = MASTER::Personas.list
    skip "No personas available" if personas.empty?
    
    result = MASTER::Personas.activate(personas.first)
    assert result.ok?, "Activating valid persona should succeed"
  end

  def test_activate_invalid_persona
    result = MASTER::Personas.activate("nonexistent_persona_xyz")
    refute result.ok?, "Activating invalid persona should fail"
    assert_match(/not found/, result.error)
  end

  def test_deactivate_persona
    result = MASTER::Personas.deactivate
    assert result.ok?, "Deactivating should succeed"
  end

  def test_active_status
    MASTER::Personas.deactivate
    refute MASTER::Personas.active?, "Should not be active after deactivate"
  end
end
