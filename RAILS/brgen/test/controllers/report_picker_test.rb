# frozen_string_literal: true

require "test_helper"

# The report control asks why: a moderator triages by reason and details, and
# a button that always sent "other" gave them neither.
class ReportPickerTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    host! "brgen.no"
    @author = person("rp_author")
    @reader = person("rp_reader")

    community = Community.create!(slug: "rp-#{SecureRandom.hex(3)}", name: "Rapport", user: @author, city: @city)
    @post = Post.create!(user: @author, community:, city: @city, title: "Rapporterbar", content: "hei")
    post session_path, params: { email_address: @reader.email_address, password: "password123" }
  end

  def person(prefix)
    User.strict_loading(false).create!(email_address: "#{prefix}_#{SecureRandom.hex(3)}@brgen.no",
                                       password: "password123", username: "#{prefix}_#{SecureRandom.hex(3)}",
                                       guest: false)
  end

  test "the post page offers reasons, other preselected, and a details field" do
    get post_path(@post)

    picker = "#report_#{ActionView::RecordIdentifier.dom_id(@post)} details form[action=?]"
    assert_select picker, reports_path do
      assert_select "fieldset legend", I18n.t("report_picker.legend")
      assert_select "input[type=radio][name=reason]", ModerationReport::PICKER_REASONS.size
      assert_select "input[type=radio][name=reason][value=other][checked]"
      assert_select "label", text: I18n.t("report_picker.reasons.abuse")
      assert_select "textarea[name=details][maxlength=?]", ModerationReport::DETAILS_LIMIT.to_s
    end
  end

  test "the chosen reason and the details reach the report" do
    post reports_path, params: { target_gid: @post.to_signed_global_id.to_s, reason: "abuse",
                                 details: "Hetsende kommentarer" }

    report = ModerationReport.find_by!(reportable: @post, user: @reader)
    assert_equal "abuse", report.reason
    assert_equal "Hetsende kommentarer", report.details
  end

  test "a reason outside the list files as other instead of failing" do
    post reports_path, params: { target_gid: @post.to_signed_global_id.to_s, reason: "nonsense" }

    assert_response :redirect
    assert_equal "other", ModerationReport.find_by!(reportable: @post, user: @reader).reason
  end
end
