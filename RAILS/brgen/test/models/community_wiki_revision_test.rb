# frozen_string_literal: true

require "test_helper"

# The history a wiki page keeps. Its own test because the page's guarantee —
# that an edit is recoverable — is only as good as what these rows hold.
class CommunityWikiRevisionTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @author = User.strict_loading(false).create!(
      email_address: "rev_author@brgen.no", password: "password123", username: "rev_author", guest: false
    )
    @community = Community.create!(name: "Rev #{SecureRandom.hex(3)}", slug: "rev-#{SecureRandom.hex(3)}", user: @author)
    @page = @community.wiki_pages.create!(title: "Regler", body: "Første", updated_by: @author)
  end

  teardown { ActsAsTenant.current_tenant = nil }

  test "a revision holds a body and points at its page" do
    revision = @page.revisions.create!(body: "Noe eldre", user: @author)

    assert_equal @page.id, revision.page_id
    assert_predicate CommunityWikiRevision.new(page: @page), :invalid?
  end

  test "newest first, so the history reads as a history" do
    @page.revise!(body: "Andre", user: @author)
    travel 1.minute
    @page.revise!(body: "Tredje", user: @author)

    assert_equal [ "Andre", "Første" ], @page.reload.revisions.map(&:body)
  end

  # An account can be deleted; losing it must not take the page's history with
  # it, so the author is optional and the row survives.
  test "the history outlives its author" do
    @page.revise!(body: "Andre", user: @author)
    revision = @page.revisions.first
    revision.update!(user: nil)

    assert_nil revision.reload.user_id
    assert_predicate revision, :valid?
  end

  test "deleting the page takes its history with it" do
    @page.revise!(body: "Andre", user: @author)

    assert_difference -> { CommunityWikiRevision.count }, -1 do
      CommunityWikiPage.find(@page.id).destroy
    end
  end
end
