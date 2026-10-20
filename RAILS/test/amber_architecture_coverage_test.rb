# frozen_string_literal: true

# Amber's architecture record is the "Architecture" section of its README, where
# d120b9348 and 6b2075234 folded the old ARCHITECTURE.md. An earlier record fell
# months behind the code because nothing read it, so this test reads it: every
# model, service and job must be named there.

require "minitest/autorun"

class AmberArchitectureCoverageTest < Minitest::Test
  ROOT = File.expand_path("../amber", __dir__)
  DOC = File.join(ROOT, "README.md")

  # Concerns are mixins, not components; ApplicationRecord/Job are framework base
  # classes. Everything else owes the document a mention.
  SKIP = %w[application_record application_job application_controller].freeze

  def test_architecture_document_exists
    assert_match(/^## Architecture$/, File.read(DOC),
                 "RAILS/amber/README.md lost its Architecture section — recover it from git history, do not rewrite it")
  end

  def test_every_component_is_named_in_the_architecture_document
    doc = File.read(DOC)
    missing = components.reject { |name| doc.include?(camelize(name)) }

    assert_empty missing.sort,
                 "components absent from README.md:#{missing.sort.join(', ')} — " \
                 "add them to a layer or the service catalog"
  end

  # A JSON vector column reads like something to migrate. The reason it is not
  # sits on the model, where the person about to migrate it looks first.
  def test_vector_decision_stays_recorded
    model = File.join(ROOT, "app/models/garment_embedding.rb")
    schema = File.read(File.join(ROOT, "db/schema.rb"))

    return unless schema.include?(%(t.json "vector"))

    assert_includes File.read(model), "pgvector",
                    "GarmentEmbedding#vector is still JSON-backed but garment_embedding.rb no longer says why"
  end

  private

  def components
    %w[models services jobs].flat_map do |dir|
      Dir[File.join(ROOT, "app", dir, "*.rb")].map { |path| File.basename(path, ".rb") }
    end.uniq - SKIP
  end

  def camelize(name)
    name.split("_").map(&:capitalize).join
  end
end
