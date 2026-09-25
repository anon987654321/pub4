# frozen_string_literal: true

require "test_helper"

class PortsControllerTest < ActionDispatch::IntegrationTest
  # Shared::ApplicationSetup declares morph refreshes with the scroll kept, and
  # the page is what has to carry that to Turbo.
  def test_the_page_tells_turbo_to_morph_refreshes_and_keep_the_scroll
    get root_url
    assert_select "head meta[name='turbo-refresh-method'][content='morph']", 1
    assert_select "head meta[name='turbo-refresh-scroll'][content='preserve']", 1
  end

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

  def test_a_row_states_its_update_age_in_the_reader_s_language
    seed_port.update!(last_updated: 400.days.ago.to_date)
    get root_url
    assert_response :success
    assert_select "span.data-state.data-state--stale", text: I18n.t("ports.age_stale", count: 400)
    assert_not_includes response.body, "stale · 400d"
  end

  def test_a_port_page_marks_a_stale_update_and_labels_its_dependency_tree
    git = seed_port
    git.update!(last_updated: 400.days.ago.to_date)
    gettext = Port.create!(platform: git.platform, category: git.category, name: "gettext", version: "1", pkgpath: "devel/gettext")
    Dependency.create!(port: git, depends_on: gettext, dep_type: "build")

    get port_url(git)
    assert_response :success
    assert_select "dd span.data-state.data-state--stale", text: /#{Regexp.escape(I18n.t("ports.stale", count: 400))}\z/
    assert_select "section[aria-label=?] ul[role=tree][aria-label=?] li[role=treeitem]",
                  I18n.t("ports.tree_heading"), I18n.t("ports.tree_heading")
  end

  def test_the_updated_sort_has_a_control_on_the_page
    seed_port
    get root_url
    assert_response :success
    assert_includes response.body, ports_path(sort: "updated")
  end

  def test_a_search_with_no_results_renders_the_empty_state
    port = seed_port
    get ports_url(q: "zzzz-no-such-port")
    assert_response :success
    assert_select "#ports a[href=?]", port_path(port), count: 0
    assert_includes response.body, I18n.t("empty.no_ports")
    assert_includes response.body, I18n.t("ports.empty_body")
    assert_not_includes response.body, I18n.t("ports.empty_unimported")
  end

  def test_the_review_notice_is_translated
    port = seed_port
    # The fixture points at /usr/ports, which exists on vm23, so the review
    # would compare against a real Makefile there and add a version mismatch.
    port.platform.update!(tree_path: "/does/not/exist")
    user = User.strict_loading(false).create!(email_address: "rev-#{SecureRandom.hex(4)}@bsdports.test", password: "password")
    post session_path, params: { email_address: user.email_address, password: "password" }

    post review_port_path(port)

    issues = [ I18n.t("flash.review_issue.missing_homepage"), I18n.t("flash.review_issue.weak_comment") ].join(", ")
    assert_equal I18n.t("flash.review_issues", issues: issues), flash[:notice]
  end

  def test_a_port_page_revalidates_until_a_comment_or_the_viewer_changes
    port = seed_port
    get port_path(port)
    assert_response :success
    etag = response.headers["ETag"]
    assert etag, "ports#show must answer with an ETag"
    assert_no_match(/public/, response.headers["Cache-Control"].to_s)

    get port_path(port), headers: { "If-None-Match" => etag }
    assert_response :not_modified

    user = User.strict_loading(false).create!(email_address: "etag-#{SecureRandom.hex(4)}@bsdports.test", password: "password")
    Comment.create!(user:, port:, content: "builds fine on arm64")
    get port_path(port), headers: { "If-None-Match" => etag }
    assert_response :success, "a new comment must change the port page's ETag"

    etag = response.headers["ETag"]
    post session_path, params: { email_address: user.email_address, password: "password" }
    get port_path(port), headers: { "If-None-Match" => etag }
    assert_response :success, "signing in must not revalidate the signed-out copy"
  end

  # bsdports has no guests, so allow_unauthenticated_access skips
  # resume_session on public pages; authenticated? has to resume it there.
  def test_a_signed_in_reader_sees_their_own_controls_on_a_public_port_page
    port = seed_port
    get port_path(port)
    assert_select "#port_watch_#{port.id}", count: 0

    user = User.strict_loading(false).create!(email_address: "reader-#{SecureRandom.hex(4)}@bsdports.test", password: "password")
    post session_path, params: { email_address: user.email_address, password: "password" }
    get port_path(port)
    assert_response :success
    assert_select "#port_watch_#{port.id} form[action=?]", watch_port_path(port)
  end

  def test_a_maintainer_page_revalidates_until_its_ports_change
    port = seed_port
    maintainer = Maintainer.create!(name: "Jane Porter")
    port.update!(maintainer_id: maintainer.id)

    get maintainer_path(maintainer)
    assert_response :success
    etag = response.headers["ETag"]
    get maintainer_path(maintainer), headers: { "If-None-Match" => etag }
    assert_response :not_modified

    port.update!(version: "2.5")
    get maintainer_path(maintainer), headers: { "If-None-Match" => etag }
    assert_response :success
  end

  def test_the_html_index_is_not_cached_for_everyone
    get root_url
    assert_response :success
    assert_no_match(/public|max-age=600/, response.headers["Cache-Control"].to_s)
  end

  private

  # A Port needs a platform and a category; the fixtures carry only the platform.
  def seed_port
    platform = platforms(:openbsd)
    category = Category.create!(platform:, name: "devel", slug: "devel")
    Port.create!(platform:, category:, name: "git", version: "2.4", pkgpath: "devel/git")
  end
end
