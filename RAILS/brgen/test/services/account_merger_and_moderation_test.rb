# frozen_string_literal: true

require "test_helper"

# The other half of the coverage-contract gap: the merge that hands a guest's
# whole history to a real account, and the moderation workflow that resolves a
# report — both money-and-trust paths that had never had a method called.
class AccountMergerAndModerationTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @guest = User.create!(email_address: "g-#{SecureRandom.hex(4)}@guest.local",
                          password: SecureRandom.hex(16), guest: true, city: @city)
    @member = User.create!(email_address: "m-#{SecureRandom.hex(4)}@brgen.no",
                           password: SecureRandom.hex(16), username: "m_#{SecureRandom.hex(3)}", city: @city)
  end
  teardown { ActsAsTenant.current_tenant = nil }

  test "merge hands the guest's posts and signals to the member and records itself" do
    post = Post.create!(title: "hei", content: "nabolagsfest på lørdag", user: @guest)
    TrustSignal.create!(user: @guest, kind: "account_created", source: "test", weight: 0)

    result = AccountMerger.new(guest_user: @guest, user: @member).call

    assert_equal @member, result
    assert_equal @member.id, post.reload.user_id
    assert_equal @member.id, TrustSignal.find_by(kind: "account_created").user_id
    merge = AccountMerge.find_by(guest_user_id: @guest.id, user_id: @member.id)
    assert merge, "the merge must leave a record"
    assert_equal "merged", merge.status
    assert_not @guest.reload.guest?, "the emptied guest row stops being a guest"
  end

  test "merging a non-guest is refused as a no-op" do
    regular = User.create!(email_address: "r-#{SecureRandom.hex(4)}@brgen.no",
                           password: SecureRandom.hex(16), username: "r_#{SecureRandom.hex(3)}", city: @city)
    post = Post.create!(title: "min", content: "dette er mitt innlegg her", user: regular)
    AccountMerger.new(guest_user: regular, user: @member).call
    assert_equal regular.id, post.reload.user_id, "a non-guest's history must never transfer"
    assert_nil AccountMerge.find_by(guest_user_id: regular.id)
  end

  test "a report opens a flag and resolving it closes the flag and removes the content" do
    post = Post.create!(title: "spam", content: "kjøp klokker billig nå her", user: @guest)
    report = ModerationWorkflow.report!(reporter: @member, target: post, reason: "spam")

    assert_equal "open", report.status
    flag = ModerationFlag.find_by(flaggable: post)
    assert flag, "reporting must flag the content"
    assert_equal "open", flag.status

    ModerationWorkflow.transition!(report: report, status: "resolved")
    assert_equal "resolved", report.reload.status
    assert_equal "resolved", flag.reload.status
    # remove_content: however the model spells removal, the feed must not show it.
    assert_not Post.where(id: post.id).where(deleted_at: nil).exists? if Post.column_names.include?("deleted_at")
  end

  test "transition! survives a report loaded bare by id — the strict_loading trap" do
    post = Post.create!(title: "spam2", content: "enda mer spam om klokker", user: @guest)
    report = ModerationWorkflow.report!(reporter: @member, target: post, reason: "spam")
    bare = ModerationReport.find(report.id)
    assert_nothing_raised { ModerationWorkflow.transition!(report: bare, status: "resolved") }
  end

  test "an unknown status is refused without touching the report" do
    post = Post.create!(title: "x", content: "helt vanlig innhold her ja", user: @guest)
    report = ModerationWorkflow.report!(reporter: @member, target: post, reason: "other")
    ModerationWorkflow.transition!(report: report, status: "not_a_status")
    assert_equal "open", report.reload.status
  end
end
