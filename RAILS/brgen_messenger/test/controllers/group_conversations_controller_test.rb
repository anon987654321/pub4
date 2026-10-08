# frozen_string_literal: true

require "test_helper"

class GroupConversationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @founder = create_user("grp_founder")
    @friend = create_user("grp_friend")
    @colleague = create_user("grp_colleague")
    @outsider = create_user("grp_outsider")
    ActsAsTenant.current_tenant = @city
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

  def make_group
    Conversation.create_group!(creator: @founder, name: "Turgruppa", users: [ @friend, @colleague ])
  end

  test "creating a group seats the founder as its op" do
    sign_in_as(@founder)

    assert_difference -> { Conversation.count }, 1 do
      post groups_path, params: { name: "Turgruppa", usernames: "grp_friend, grp_colleague" }
    end
    group = Conversation.order(:created_at).last
    assert_equal "Turgruppa", group.name
    assert_equal 3, group.participants.count
    assert group.admin?(@founder)
    assert_not group.admin?(@friend)
  end

  # A typo in one name should not throw away the other two.
  test "unknown usernames are skipped, not fatal" do
    sign_in_as(@founder)

    post groups_path, params: { name: "Turgruppa", usernames: "grp_friend, nobody_here" }
    group = Conversation.order(:created_at).last
    assert_equal 2, group.participants.count
  end

  test "a group with nobody in it is refused" do
    sign_in_as(@founder)

    assert_no_difference -> { Conversation.count } do
      post groups_path, params: { name: "Tom gruppe", usernames: "nobody_here" }
    end
    assert_redirected_to new_group_path
  end

  test "only an op renames the group" do
    group = make_group
    sign_in_as(@friend)

    patch group_path(group), params: { conversation: { name: "Kapret" } }
    assert_response :forbidden
    assert_equal "Turgruppa", group.reload.name

    sign_in_as(@founder)
    patch group_path(group), params: { conversation: { name: "Fjellturer" } }
    assert_equal "Fjellturer", group.reload.name
  end

  test "any member adds, only an op removes someone else" do
    group = make_group
    sign_in_as(@friend)

    post group_members_path(group), params: { username: "grp_outsider" }
    assert_includes group.reload.participants, @outsider

    delete group_member_path(group, @colleague)
    assert_response :forbidden

    sign_in_as(@founder)
    delete group_member_path(group, @colleague)
    assert_not_includes group.reload.participants, @colleague
  end

  # Leaving is always yours to do, and a group without an op could never be
  # renamed or moderated again — so the room passes to whoever has been in it
  # longest rather than trapping the last op in it.
  test "the last op leaving hands the group to the longest-standing member" do
    group = make_group
    sign_in_as(@founder)

    delete group_member_path(group, @founder)
    assert_redirected_to conversations_path
    assert_not_includes group.reload.participants, @founder
    assert group.reload.admin?(@friend)
  end

  test "a stranger cannot touch the group at all" do
    group = make_group
    sign_in_as(@outsider)

    post group_members_path(group), params: { username: "grp_outsider" }
    assert_response :not_found
  end
test "the group thread page carries its roster and the rename form" do
  group = make_group
  sign_in_as(@founder)

  get conversation_path(group)
  assert_response :success
  assert_includes response.body, "grp_friend"
  assert_includes response.body, group_member_path(group, @friend)
  assert_includes response.body, group_path(group)
end

test "a member sees the roster without the rename form" do
  group = make_group
  sign_in_as(@friend)

  get conversation_path(group)
  assert_response :success
  assert_includes response.body, group_member_path(group, @friend)
  assert_not_includes response.body, group_member_path(group, @colleague)
end
test "the new-group form renders" do
  sign_in_as(@founder)

  get new_group_path
  assert_response :success
  assert_includes response.body, groups_path
end
end
