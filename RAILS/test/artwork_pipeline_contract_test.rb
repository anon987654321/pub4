# frozen_string_literal: true

require "minitest/autorun"
require "yaml"

class ArtworkPipelineContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  MASTER_ROOT = File.join(ROOT, "..", "MASTER")

  def test_house_artwork_law_forbids_raw_diffusion_and_requires_grade
    law = YAML.safe_load_file(File.join(MASTER_ROOT, "data/artwork.yml"))
    assert_equal true, law.dig("house", "grade_required")
    assert_equal true, law.dig("house", "provenance_required")
    assert_equal false, law.dig("lanes", "g4", "allowed")
    assert_equal 3, law.dig("rubric", "max_accent_zones")
  end

  def test_onboarding_artwork_uses_shared_publication_boundary
    source = File.read(File.join(ROOT, "shared/app/services/shared/onboarding_artwork.rb"))
    assert_includes source, 'VERSION = "v2"'
    assert_includes source, "ArtworkPipeline.publish_remote"
    refute_includes source, 'File.binwrite(temporary, URI.open(source'
  end

  def test_newsletter_replicate_requests_are_seeded_and_published_through_postpro
    source = File.read(File.join(ROOT, "shared/app/services/shared/newsletter_visuals.rb"))
    assert_includes source, "seed:"
    assert_includes source, "output_format: "webp""
    assert_includes source, "ArtworkPipeline.publish_remote"
    assert_includes source, 'filename = "#{prefix.to_s.parameterize}-#{seed}.jpg"'
  end

  def test_seed_ledger_is_append_only_and_hashed
    source = File.read(File.join(ROOT, "shared/app/services/shared/artwork_pipeline.rb"))
    assert_includes source, "File::WRONLY | File::CREAT | File::APPEND"
    assert_includes source, 'Digest::SHA256.file(destination).hexdigest'
  end
end
