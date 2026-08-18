# frozen_string_literal: true

require "test_helper"

class LinkPreviewTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @sender = User.strict_loading(false).create!(
      email_address: "lp_sender@brgen.no", password: "password123", username: "lp_sender", guest: false
    )
    @friend = User.strict_loading(false).create!(
      email_address: "lp_friend@brgen.no", password: "password123", username: "lp_friend", guest: false
    )
    @conversation = Conversation.find_or_create_direct(@sender, @friend)
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def say(content)
    Message.create!(conversation: @conversation, sender: @sender, content: content, message_type: "text")
  end

  test "the first https link in a message becomes its preview" do
    message = say("Se her https://example.com/artikkel og si hva du synes")

    assert_equal "https://example.com/artikkel", LinkPreview.find(message.reload.link_preview_id).url
  end

  # http:// is not upgraded on the sender's behalf: fetching it would be an
  # unencrypted request made for them, and https is a guess about a server that
  # did not offer it.
  test "plain http and bare text carry no preview" do
    assert_nil say("http://example.com/gammelt").reload.link_preview_id
    assert_nil say("ingen lenke her").reload.link_preview_id
  end

  test "trailing punctuation is not part of the URL" do
    assert_equal "https://example.com/x", LinkPreview.first_url_in("les https://example.com/x.")
  end

  # The same article pasted into twenty rooms is one fetch, not twenty — this
  # app should not be an amplifier pointed at whoever was linked.
  test "the same URL is one row across messages" do
    a = say("https://example.com/delt")
    b = say("igjen: https://example.com/delt")

    assert_equal a.reload.link_preview_id, b.reload.link_preview_id
    assert_equal 1, LinkPreview.where(url: "https://example.com/delt").count
  end

  # A dead link must not become a fetch on every render of the thread.
  test "a failure is recorded rather than retried on read" do
    preview = LinkPreview.create!(url: "https://example.com/borte", status: "failed", fetched_at: Time.current)

    assert_not preview.ok?
    assert_not preview.stale?
  end

  test "an unsafe host is refused before any request is made" do
    assert_not OutboundHttp.public_https?(URI("https://127.0.0.1/x"))
    assert_not OutboundHttp.public_https?(URI("https://169.254.169.254/latest/meta-data"))
  end
end
