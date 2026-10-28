# frozen_string_literal: true

require_relative "test_helper"
require File.join(Master::ROOT, "law", "definition")

# A path-scoped Law that names a directory nobody has can never fire, and
# nothing reports it: applies? is false for every file, so the scan finds
# nothing and reads as clean. The marketplace is the sibling
# RAILS/brgen_marketplace/ app, so that is what the commerce scopes must name.
class TestLawCommerce < Minitest::Test
  REPO = File.expand_path("../..", __dir__)

  def setup
    Law.load_all(File.join(Master::ROOT, "law"))
  end

  def definition(id) = Law.definitions.fetch(id)

  def test_every_commerce_law_scope_names_a_directory_that_exists
    %i[COMMERCE_AMBER_DOES_NOT_OWN_BRGEN COMMERCE_BRGEN_DOES_NOT_OWN_AMBER
       COMMERCE_EXTERNAL_SOURCES_STAY_EXPLAINABLE].each do |id|
      scope = definition(id).path

      assert File.directory?(File.join(REPO, scope)), "#{id} is scoped to #{scope}, which does not exist"
    end
  end

  def test_brgen_marketplace_law_fires_on_a_marketplace_file_that_ranks_wardrobe
    law = definition(:COMMERCE_BRGEN_DOES_NOT_OWN_AMBER)
    file = "RAILS/brgen_marketplace/app/services/marketplace/ranking_service.rb"

    assert File.file?(File.join(REPO, file)), "the fixture path moved; point this at a real marketplace service"
    assert law.applies?(file, "ruby")
    refute_empty law.scan("TasteRanker.new(Current.user).rank(listings)\n", file:)
    assert_empty law.scan(law.good, file:)
  end

  def test_brgen_marketplace_law_does_not_reach_amber_itself
    refute definition(:COMMERCE_BRGEN_DOES_NOT_OWN_AMBER).applies?("RAILS/amber/app/services/taste_ranker.rb", "ruby")
  end

  def test_real_marketplace_sources_hold_the_boundary
    law = definition(:COMMERCE_BRGEN_DOES_NOT_OWN_AMBER)
    offenders = Dir.glob(File.join(REPO, "RAILS", "brgen_marketplace", "app", "**", "*.rb")).flat_map do |path|
      relative = path.delete_prefix("#{REPO}/")
      law.scan(File.read(path), file: relative).map { |hit| "#{relative}: #{hit}" }
    end

    assert_empty offenders
  end
end
