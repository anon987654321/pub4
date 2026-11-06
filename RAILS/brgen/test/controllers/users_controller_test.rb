# frozen_string_literal: true

require "test_helper"

# The quota wall tells a guest to "Sign up to post more". Until this existed
# there was nowhere to sign up: /users/new was a 404, the sign-in page only
# offered sign-in, and the OAuth buttons render only for providers configured
# in the environment.
class UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    host! "brgen.no"
  end

  test "signup form is reachable without an account" do
    get new_user_path
    assert_response :success
    # Assert the translation, not the English string. brgen.no renders in nb, so
    # a literal "Create account" started failing the moment the page was
    # localised — through the key it follows whatever locale the host resolves to.
    assert_includes response.body, I18n.t("auth.create_account")
  end

  test "the sign-in page offers a way to create an account" do
    get new_session_path
    assert_response :success
    assert_match(new_user_path, response.body)
  end

  test "creating an account signs the visitor in as a real user" do
    post users_path, params: { accept_terms: "1", accept_age: "1", user: {
      email_address: "newcomer@example.test",
      username: "newcomer",
      password: "password123",
      password_confirmation: "password123"
    } }
    assert_redirected_to root_path

    user = User.find_by(email_address: "newcomer@example.test")
    assert user, "expected the account to exist"
    assert_not user.guest?
    assert user.sessions.any?, "expected a session for the new account"
    assert_equal I18n.t("shared.email_verification.signup_notice"), flash[:notice]
  end

  test "a profile lists only posts that name their author and the viewer may read" do
    author = User.create!(email_address: "profil-#{SecureRandom.hex(4)}@brgen.no", password: "password123",
                          username: "profil_#{SecureRandom.hex(3)}")
    club = Community.create!(slug: "lukket-#{SecureRandom.hex(3)}", name: "Lukket", user: User.create!(
      email_address: "eier-#{SecureRandom.hex(4)}@brgen.no", password: "password123"
    ), city: @city, privacy: "private")
    titles = {
      named: "Navngitt #{SecureRandom.hex(3)}",
      anonymous: "Anonym #{SecureRandom.hex(3)}",
      live: "Live #{SecureRandom.hex(3)}",
      removed: "Fjernet #{SecureRandom.hex(3)}",
      private: "Lukket #{SecureRandom.hex(3)}"
    }
    write = ->(title, community: nil, **state) do
      Post.create!(user: author, city: @city, community:, title:, content: "hei").tap do |row|
        row.update_columns(state) if state.any?
      end
    end

    write.(titles[:named])
    write.(titles[:anonymous], anonymous: true)
    write.(titles[:live], latitude: 60.39, longitude: 5.32)
    write.(titles[:removed], removed_at: Time.current)
    write.(titles[:private], community: club)

    get user_path(author)

    assert_response :success
    assert_includes response.body, titles[:named]
    %i[anonymous live removed private].each do |kind|
      refute_includes response.body, titles[kind], "the profile shows the #{kind} post"
    end
  end

  test "a profile header counts every readable post and shows avatar and join date" do
    author = User.create!(email_address: "teller-#{SecureRandom.hex(4)}@brgen.no", password: "password123",
                          username: "teller_#{SecureRandom.hex(3)}", created_at: Time.zone.local(2025, 3, 5))
    27.times { |i| Post.create!(user: author, city: @city, title: "Innlegg #{i}", content: "hei") }

    get user_path(author)

    assert_response :success
    assert_select ".profile-header", text: /#{Regexp.escape(I18n.t("community.posts_count", count: 27))}/
    assert_select ".profile-header img.avatar[src=?]", author.avatar_url
    member_since = I18n.t("profile.member_since", date: I18n.l(author.created_at.to_date, format: "%B %Y"))
    assert_select ".profile-header", text: /#{Regexp.escape(member_since)}/
    assert_select "ul.post-feed > li", 25
  end

  test "the profile edit screen links the account page" do
    me = User.create!(email_address: "konto-#{SecureRandom.hex(4)}@brgen.no", password: "password123",
                      username: "konto_#{SecureRandom.hex(3)}")
    post session_path, params: { email_address: me.email_address, password: "password123" }

    get edit_user_path(me)

    assert_response :success
    assert_select "a[href=?]", account_path
  end

  test "a deletion-pending public profile is not reachable" do
    subject = User.create!(
      email_address: "leaving-#{SecureRandom.hex(4)}@brgen.no",
      password: "password123",
      username: "leaving_#{SecureRandom.hex(3)}"
    )
    subject.update_columns(deleted_at: Time.current, deletion_scheduled_at: 7.days.from_now)

    get user_path(subject)

    assert_response :not_found
  end

  test "a signed-in user is sent past sign-up, and a second post creates nothing" do
    post users_path, params: { accept_terms: "1", accept_age: "1", user: {
      email_address: "already@example.test", password: "password123", password_confirmation: "password123"
    } }

    get new_user_path
    assert_redirected_to root_path

    assert_no_difference -> { User.where(guest: false).count } do
      post users_path, params: { accept_terms: "1", accept_age: "1", user: {
        email_address: "second@example.test", password: "password123", password_confirmation: "password123"
      } }
    end
    assert_redirected_to root_path
  end

  test "signup carries the guest's posts onto the new account" do
    # The first hit builds a soft guest without writing a row; the second, which
    # carries the session cookie back, is what mints it (Shared::Authentication).
    get root_path
    get root_path
    guest = User.where(guest: true).order(created_at: :desc).first
    guest.update_columns(latitude: 60.39, longitude: 5.32, location_updated_at: Time.current)
    # Was `post live_path`. The Live surface is gone and its one distinct step —
    # the coarsened geo stamp — is `nearby` on the ordinary composer now, so this
    # still posts the same kind of row through the path that replaced it.
    post posts_path, params: { post: { content: "Guest note before signing up", nearby: "1" } }
    guest_post = Post.where(user: guest).order(created_at: :desc).first
    assert guest_post, "expected the guest to have posted"

    post users_path, params: { accept_terms: "1", accept_age: "1", user: {
      email_address: "carryover@example.test",
      password: "password123",
      password_confirmation: "password123"
    } }
    assert_redirected_to root_path

    user = User.find_by(email_address: "carryover@example.test")
    assert_equal user.id, Post.strict_loading(false).find(guest_post.id).user_id
    assert_equal I18n.t("shared.email_verification.signup_notice_guest_merged"), flash[:notice]
  end

  test "signup without accepting terms creates no account" do
    assert_no_difference -> { User.where(guest: false).count } do
      post users_path, params: { user: {
        email_address: "noterms@example.test",
        password: "password123",
        password_confirmation: "password123"
      } }
    end
    assert_response :unprocessable_entity
  end

  test "an invalid signup re-renders the form instead of erroring" do
    assert_no_difference -> { User.where(guest: false).count } do
      post users_path, params: { user: { email_address: "", password: "x", password_confirmation: "y" } }
    end
    assert_response :unprocessable_entity
  end

  # RI-003: malformed email input must be rejected before a real account exists.
  def test_RI_003_malformed_email_is_rejected_without_account
    email = "not-an-email"
    username = "ri003_#{SecureRandom.hex(5)}"
    params = {
      accept_terms: "1",
      accept_age: "1",
      user: {
        email_address: email,
        username:,
        password: "password123",
        password_confirmation: "password123"
      }
    }

    assert_no_difference -> { User.where(guest: false).count } do
      post users_path, params:
    end

    assert_response :unprocessable_entity
    assert_nil User.find_by(email_address: email)
  end

  # The sign-in tab showed only the city name.
  test "the sign-in page names itself in the tab" do
    get new_session_path

    assert_select "title", /#{Regexp.escape(I18n.t("auth.sign_in"))}/
  end

  # Blocking asks first, as the messenger's block does, and the account itself
  # can be reported from the profile, not only its posts and messages.
  test "another member's profile confirms a block and offers a report" do
    viewer = User.create!(email_address: "uc-viewer@brgen.no", password: "password123", username: "uc_viewer")
    other = User.create!(email_address: "uc-other@brgen.no", password: "password123", username: "uc_other")
    post session_path, params: { email_address: viewer.email_address, password: "password123" }

    get user_path(other)

    assert_response :success
    confirm = I18n.t("messages.confirm_block")
    assert_select "form[action=?] button[data-turbo-confirm=?]", block_user_path(other), confirm
    assert_select "#report_#{ActionView::RecordIdentifier.dom_id(other)} form[action=?]", reports_path
  end
end
