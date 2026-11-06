# frozen_string_literal: true

require "test_helper"

# The admin queue opens on open reports, says what each report is about with a
# link and an excerpt, and words reason and status in the reader's language.
class AdminReportsQueueTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    host! "brgen.no"
    @previous_admin = ENV["BRGEN_ADMIN_EMAIL"]
    ENV["BRGEN_ADMIN_EMAIL"] = "admin-queue@brgen.no"
  end

  teardown do
    ENV["BRGEN_ADMIN_EMAIL"] = @previous_admin
    ActsAsTenant.current_tenant = nil
  end

  def user(prefix, email: nil)
    User.strict_loading(false).create!(
      email_address: email || "#{prefix}-#{SecureRandom.hex(4)}@brgen.no",
      password: "password123", city: @city,
    )
  end

  def sign_in_admin
    admin = user("admin", email: ENV.fetch("BRGEN_ADMIN_EMAIL"))
    admin.update!(email_verified_at: Time.current) if admin.respond_to?(:email_verified_at)
    post session_path, params: { email_address: admin.email_address, password: "password123" }
  end

  test "the queue shows open reports by default and every status on request" do
    ActsAsTenant.with_tenant(@city) do
      reporter = user("reporter")
      community = Community.create!(name: "Queue #{SecureRandom.hex(3)}", slug: "queue-#{SecureRandom.hex(4)}")
      open_post = Post.create!(user: user("a"), community:, title: "Åpen sak om sykkeltyveri",
                               content: "…")
      done_post = Post.create!(user: user("b"), community:, title: "Ferdig sak om parkering",
                               content: "…")
      ModerationReport.create!(user: reporter, reportable: open_post, reason: "unsafe", status: "open")
      ModerationReport.create!(user: reporter, reportable: done_post, reason: "spam", status: "resolved")

      sign_in_admin
      get admin_reports_path

      assert_response :success
      assert_includes response.body, "Åpen sak om sykkeltyveri"
      assert_not_includes response.body, "Ferdig sak om parkering"
      assert_select "a[href=?]", post_path(open_post), text: /Åpen sak om sykkeltyveri/
      assert_not_includes response.body, "Post##{open_post.id}"
      heading = "#{I18n.t('moderation_queue.reasons.unsafe')} · #{I18n.t('moderation_queue.statuses.open')}"
      assert_select "strong", text: heading
      assert_select "nav a[aria-current=page]", text: I18n.t("moderation_queue.filters.open")

      get admin_reports_path(status: "all")
      assert_includes response.body, "Ferdig sak om parkering"
      heading = "#{I18n.t('moderation_queue.reasons.spam')} · #{I18n.t('moderation_queue.statuses.resolved')}"
      assert_select "strong", text: heading
    end
  end

  test "a reported comment links to its post at the comment, with an excerpt" do
    ActsAsTenant.with_tenant(@city) do
      community = Community.create!(name: "Queue #{SecureRandom.hex(3)}", slug: "queue-#{SecureRandom.hex(4)}")
      post_record = Post.create!(user: user("a"), community:, title: "Tråd", content: "…")
      comment = Comment.create!(user: user("c"), commentable: post_record,
                                content: "Dette er en stygg kommentar om naboen")
      ModerationReport.create!(user: user("r"), reportable: comment, reason: "abuse", status: "open")

      sign_in_admin
      get admin_reports_path

      assert_select "a[href=?]", post_path(post_record, anchor: "comment_#{comment.id}"),
                    text: /stygg kommentar om naboen/
    end
  end
end
