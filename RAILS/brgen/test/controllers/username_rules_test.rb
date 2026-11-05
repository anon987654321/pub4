# frozen_string_literal: true

require "test_helper"

# A username chosen on the profile form is one a mention can name, at a length
# a header can show, and free in every letter case; the form can ask first.
class UsernameRulesTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    host! "brgen.no"
    @me = person("navn_#{SecureRandom.hex(3)}")
    @other = person("Opptatt_#{SecureRandom.hex(3)}")
    post session_path, params: { email_address: @me.email_address, password: "password123" }
  end

  def person(username)
    User.create!(email_address: "#{username.downcase}@brgen.no", password: "password123", username:)
  end

  def availability(name)
    get username_availability_users_path(username: name), as: :json
    response.parsed_body
  end

  test "a name with a character a mention cannot read is refused" do
    patch user_path(@me), params: { user: { username: "kari-nordmann" } }

    assert_response :unprocessable_entity
    refute_equal "kari-nordmann", @me.reload.username
  end

  test "a name too short or too long is refused" do
    [ "ab", "a" * (User::USERNAME_LENGTH.max + 1) ].each do |name|
      patch user_path(@me), params: { user: { username: name } }

      assert_response :unprocessable_entity
    end
  end

  test "another person's name in another letter case is refused" do
    patch user_path(@me), params: { user: { username: @other.username.downcase } }

    assert_response :unprocessable_entity
  end

  test "a well formed free name is saved" do
    name = "ny_#{SecureRandom.hex(3)}"
    patch user_path(@me), params: { user: { username: name } }

    assert_equal name, @me.reload.username
  end

  test "the availability hint answers free, taken and malformed names in words" do
    free = "ledig_#{SecureRandom.hex(3)}"
    assert_equal({ "available" => true, "message" => I18n.t("profile.username_available", name: free) },
                 availability(free).slice("available", "message"))
    taken = availability(@other.username.upcase)
    assert_equal [ false, I18n.t("profile.username_taken", name: @other.username.upcase) ],
                 taken.values_at("available", "message")
    assert_equal false, availability("a b")["available"]
    assert availability(@me.username)["available"], "a person's own name is theirs to keep"
  end

  test "the form states the rule and wires the hint" do
    get edit_user_path(@me)

    assert_select "input[name='user[username]'][pattern=?][minlength='3'][maxlength='30']", User::USERNAME_PATTERN
    assert_select "[data-controller='username-availability'] [role=status][data-username-availability-target=hint]"
  end
end
