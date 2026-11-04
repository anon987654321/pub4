# frozen_string_literal: true

require "test_helper"

# An id names one element. A partial rendered once per post or per message that
# carries a fixed id breaks every label[for], aria-labelledby and turbo-stream
# target that points at it, and nothing in a browser reports it. The two pages
# that repeat a partial the most are held to unique ids here.
class DuplicateIdsTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    host! "brgen.no"
    @reader = person("ids_reader")
    @author = person("ids_author")
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def person(prefix)
    User.strict_loading(false).create!(email_address: "#{prefix}_#{SecureRandom.hex(3)}@brgen.no",
                                       password: "password123", username: "#{prefix}_#{SecureRandom.hex(3)}",
                                       guest: false, city: @city)
  end

  # Each repeated id with the elements that carry it, so a failure names them.
  def duplicate_ids
    nodes = Nokogiri::HTML5(response.body).css("[id]").group_by { |node| node["id"] }
    nodes.select { |_id, carriers| carriers.size > 1 }
         .transform_values { |carriers| carriers.map { |node| "#{node.name}.#{node['class']}" }.uniq }
  end

  test "the home feed repeats no id across its post cards" do
    community = Community.create!(name: "Ider #{SecureRandom.hex(3)}", slug: "ider-#{SecureRandom.hex(4)}")
    5.times { |n| Post.create!(user: @author, community:, title: "Innlegg #{n}", content: "Tekst #{n}") }
    post session_path, params: { email_address: @reader.email_address, password: "password123" }

    get root_path

    assert_response :success
    assert_operator css_select("[id]").size, :>, 10, "the page carried no ids to compare"
    assert_empty duplicate_ids
  end

  test "a conversation repeats no id across its messages" do
    conversation = Conversation.find_or_create_direct(@reader, @author)
    4.times do |n|
      sender = n.even? ? @author : @reader
      Message.create!(conversation:, sender:, content: "Linje #{n}", message_type: "text")
    end
    post session_path, params: { email_address: @reader.email_address, password: "password123" }

    get conversation_path(conversation)

    assert_response :success
    assert_empty duplicate_ids
  end
end
