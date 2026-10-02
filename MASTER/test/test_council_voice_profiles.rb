# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/review/council/voice_profile"
require_relative "../lib/review/council/personas"

class TestCouncilVoiceProfiles < Minitest::Test
  def test_every_current_persona_has_a_distinct_voice_profile
    personas = Master::Review::Council::Personas.load
    profiles = Master::Review::Council::VoiceProfile.unique_for(personas)

    assert_equal personas.size, profiles.size
    assert_equal personas.size, profiles.map(&:voice).uniq.size
    assert profiles.all? { |profile| profile.rate.to_s.match?(/\A[+-]\d+%/) }
    assert profiles.all? { |profile| profile.pitch.to_s.match?(/\A[+-]\d+Hz/) }
    assert profiles.all? { |profile| !profile.vernacular.to_s.empty? }
    assert profiles.all? { |profile| !profile.speech_pattern.to_s.empty? }
  end

  def test_voice_profile_is_deterministic
    persona = Master::Review::Council::Personas.load.first

    assert_equal(
      Master::Review::Council::VoiceProfile.for(persona),
      Master::Review::Council::VoiceProfile.for(persona),
    )
  end

  def test_render_adds_the_personas_speech_signature_without_changing_evidence
    persona = Master::Review::Council::Personas.load.find { |item| item.name == "Security" }
    source = "The boundary accepts untrusted input."

    rendered = Master::Review::Council::VoiceProfile.render(source, persona:)

    refute_equal source, rendered
    assert_includes rendered, "attack surface"
    assert_includes rendered, source
  end
end
