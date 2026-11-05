# frozen_string_literal: true

require "application_system_test_case"

# The tab title carries the unread DM count, kept by the tab bar's badge.
class UnreadTitleTest < ApplicationSystemTestCase
  include CityHostSystemTest

  setup do
    Brgen::CitySeed.sync! if City.table_exists? && !City.exists?(domain: "brgen.no")
    @city = City.find_by!(domain: "brgen.no")
    @reader = person("chrome_reader_#{SecureRandom.hex(2)}")
    @friend = person("chrome_friend_#{SecureRandom.hex(2)}")
  end

  test "the tab title carries the unread DM count on every page" do
    conversation = ActsAsTenant.with_tenant(@city) { Conversation.find_or_create_direct(@reader, @friend) }
    ActsAsTenant.with_tenant(@city) do
      2.times { |i| conversation.messages.create!(sender: @friend, content: "Hei #{i}", message_type: "text") }
    end

    sign_in_on_city(@reader)
    visit_city(nil, "/")
    assert wait_until { page.title.start_with?("(2) ") }, "title was #{page.title.inspect}"

    # A Turbo visit keeps the permanent tab bar and brings a new <title>.
    find("#app-tab-bar", visible: :all)
    page.execute_script("Turbo.visit('/communities')")
    assert wait_until { page.current_path == "/communities" && page.title.start_with?("(2) ") },
           "title after a Turbo visit was #{page.title.inspect}"
    assert_equal 1, page.title.scan("(2)").size, "the prefix is applied once"
  end

  private

  def person(handle)
    User.strict_loading(false).create!(
      email_address: "#{handle}@brgen.no", password: "password123", username: handle, guest: false, city: @city
    )
  end
end
