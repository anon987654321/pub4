# frozen_string_literal: true

require "test_helper"

class CommunityWikiPageTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @owner = User.strict_loading(false).create!(
      email_address: "wiki_owner@brgen.no", password: "password123", username: "wiki_owner", guest: false
    )
    @mod = User.strict_loading(false).create!(
      email_address: "wiki_mod@brgen.no", password: "password123", username: "wiki_mod", guest: false
    )
    @community = Community.create!(name: "Wiki #{SecureRandom.hex(3)}", slug: "wiki-#{SecureRandom.hex(3)}", user: @owner)
    @page = @community.wiki_pages.create!(title: "Regler for tråden", body: "Første utkast", updated_by: @owner)
  end

  teardown { ActsAsTenant.current_tenant = nil }

  test "a page is addressed by a slug of its title, unique within the community" do
    assert_equal "regler-for-traden", @page.slug

    second = @community.wiki_pages.create!(title: "Regler for tråden", body: "En annen side", updated_by: @owner)
    assert_equal "regler-for-traden-2", second.slug
  end

  # revise! rather than update!, so no caller can save a page and forget the
  # revision — a history with holes reads as if the missing edits never happened.
  test "every edit keeps the body it replaced" do
    @page.revise!(body: "Andre utkast", user: @mod)

    assert_equal "Andre utkast", @page.reload.body
    assert_equal @mod.id, @page.updated_by_id
    assert_equal [ "Første utkast" ], @page.revisions.map(&:body)
    assert_equal @owner.id, @page.revisions.first.user_id
  end

  test "saving the same body twice writes no second revision" do
    @page.revise!(body: "Første utkast", user: @mod)

    assert_empty @page.revisions
  end

  # A wiki whose history can be edited is a wiki nobody can audit.
  test "a revert is a new revision, not a deletion of the newer ones" do
    @page.revise!(body: "Andre utkast", user: @mod)
    @page.revise!(body: "Tredje utkast", user: @mod)
    first_revision = @page.revisions.last

    @page.revert_to!(first_revision, user: @owner)

    assert_equal "Første utkast", @page.reload.body
    assert_equal 3, @page.revisions.count
    assert_includes @page.revisions.map(&:body), "Tredje utkast"
  end

  test "deleting the community takes its wiki with it" do
    assert_difference -> { CommunityWikiPage.count }, -1 do
      Community.find(@community.id).destroy
    end
  end
end
