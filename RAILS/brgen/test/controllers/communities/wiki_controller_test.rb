# frozen_string_literal: true

require "test_helper"

class Communities::WikiControllerTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @owner = create_user("wc_owner")
    @member = create_user("wc_member")
    ActsAsTenant.current_tenant = @city
    @community = Community.create!(name: "Wiki #{SecureRandom.hex(3)}", slug: "wc-#{SecureRandom.hex(3)}", user: @owner)
    @community.community_memberships.create!(user: @owner, role: "owner")
    @community.community_memberships.create!(user: @member, role: "member")
    @page = @community.wiki_pages.create!(title: "Regler", body: "Vær grei", updated_by: @owner)
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def create_user(name)
    User.strict_loading(false).create!(
      email_address: "#{name}@brgen.no", password: "password123", username: name, guest: false
    )
  end

  def sign_in_as(user)
    host! "brgen.no"
    post session_path, params: { email_address: user.email_address, password: "password123" }
  end

  test "anyone who can read the community reads the wiki" do
    host! "brgen.no"

    get community_wiki_index_path(@community)
    assert_response :success
    get community_wiki_path(@community, @page)
    assert_response :success
    assert_includes response.body, "Vær grei"
  end

  # A public community's wiki open to every visitor is a spam surface, and the
  # mod queue is the only tool for cleaning one.
  test "a member cannot write it" do
    sign_in_as(@member)

    get new_community_wiki_path(@community)
    assert_response :forbidden

    patch community_wiki_path(@community, @page), params: { community_wiki_page: { body: "Kapret" } }
    assert_response :forbidden
    assert_equal "Vær grei", @page.reload.body
  end

  test "a moderator writes and edits, and the edit keeps its predecessor" do
    sign_in_as(@owner)

    assert_difference -> { CommunityWikiPage.count }, 1 do
      post community_wiki_index_path(@community), params: { community_wiki_page: { title: "Ukens tråd", body: "Hver mandag" } }
    end

    patch community_wiki_path(@community, @page), params: { community_wiki_page: { body: "Vær grei, og les reglene" } }
    assert_equal "Vær grei, og les reglene", @page.reload.body
    assert_equal [ "Vær grei" ], @page.revisions.map(&:body)
  end

  test "a moderator restores an old version and the newer one stays in the history" do
    sign_in_as(@owner)
    patch community_wiki_path(@community, @page), params: { community_wiki_page: { body: "Tulleredigering" } }
    revision = @page.revisions.first

    post revert_community_wiki_path(@community, @page), params: { revision_id: revision.id }
    assert_equal "Vær grei", @page.reload.body
    assert_includes @page.revisions.map(&:body), "Tulleredigering"
  end

  test "a private community's wiki is not readable by a stranger" do
    @community.update!(privacy: "private")
    stranger = create_user("wc_stranger")
    sign_in_as(stranger)

    get community_wiki_path(@community, @page)
    assert_response :not_found
  end
end
