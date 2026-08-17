# frozen_string_literal: true

require "test_helper"

class PortsControllerTest < ActionDispatch::IntegrationTest
  def test_root_renders_ports_index
    get root_url
    assert_response :success
  end

  def test_legal_pages_are_public
    %w[/privacy /terms /cookies].each do |path|
      get path
      assert_response :success, path
      assert_includes response.body, "legal-prose"
    end
  end

  # The controller computed @catalog_empty and @last_import and the view read
  # neither, so an unimported tree and a quiet one rendered the same page — and
  # sort=updated was reachable only by typing the query string. The strings were
  # already translated; only the markup was missing.
  def test_an_unimported_catalogue_says_so_rather_than_looking_quiet
    Port.delete_all
    get root_url
    assert_response :success
    assert_includes response.body, I18n.t("ports.empty_unimported")
  end

  def test_a_populated_catalogue_states_its_freshness
    seed_port
    get root_url
    assert_response :success
    assert(response.body.include?(I18n.t("ports.never_imported")) ||
           response.body.match?(/Siste import|Last import/),
           "the ports tree renders no import date, so its freshness is unstated")
  end

  def test_the_updated_sort_has_a_control_on_the_page
    seed_port
    get root_url
    assert_response :success
    assert_includes response.body, ports_path(sort: "updated")
  end

  private

  # A Port needs a platform and a category; the fixtures carry only the platform.
  def seed_port
    platform = platforms(:openbsd)
    category = Category.create!(platform:, name: "devel", slug: "devel")
    Port.create!(platform:, category:, name: "git", version: "2.4", pkgpath: "devel/git")
  end
end
