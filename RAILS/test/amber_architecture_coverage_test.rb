# frozen_string_literal: true

# Amber's architecture record was deleted at ee3a56e33 and nobody noticed for
# months, because nothing read it. This test reads it: every model, service and
# job must be named in ARCHITECTURE.md, so the document cannot silently fall
# behind the code the way its predecessor did.

require "minitest/autorun"

class AmberArchitectureCoverageTest < Minitest::Test
  ROOT = File.expand_path("../amber", __dir__)
  DOC = File.join(ROOT, "ARCHITECTURE.md")

  # Concerns are mixins, not components; ApplicationRecord/Job are framework base
  # classes. Everything else owes the document a mention.
  SKIP = %w[application_record application_job application_controller].freeze

  def test_architecture_document_exists
    assert File.exist?(DOC), "RAILS/amber/ARCHITECTURE.md is missing — recover it from git history, do not rewrite it"
  end

  def test_every_component_is_named_in_the_architecture_document
    doc = File.read(DOC)
    missing = components.reject { |name| doc.include?(camelize(name)) }

    assert_empty missing.sort,
                 "components absent from ARCHITECTURE.md: #{missing.sort.join(', ')} — " \
                 "add them to a layer or the service catalog"
  end

  def test_vector_decision_stays_recorded
    decisions = File.join(ROOT, "DECISIONS.md")

    assert File.exist?(decisions), "RAILS/amber/DECISIONS.md is missing"
    text = File.read(decisions)
    schema = File.read(File.join(ROOT, "db/schema.rb"))

    return unless schema.include?('t.json "vector"')

    assert_includes text, "pgvector",
                    "GarmentEmbedding#vector is still JSON-backed but DECISIONS.md no longer explains why"
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
