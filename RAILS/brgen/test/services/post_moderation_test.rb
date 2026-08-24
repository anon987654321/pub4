# frozen_string_literal: true

require "test_helper"

class PostModerationTest < ActiveSupport::TestCase
  # The 57 spam posts swept on 2026-08-12, one of each shape, verbatim.
  SPAM = [
    "Hello http://cardff.uk,\r\n\r\nWe can place your website on Google 1st page",
    "Hello there,\r\n\r\nI would like to discuss AI SEO!",
    "Greetings from DreamProxies\r\n\r\nSuperb proxy offer: premium, fast and t",
    "Для эффективного использования программы можно приобрести <a href=http"
  ].freeze

  def guest = @guest ||= User.create!(email_address: "guest_#{SecureRandom.hex(8)}@guest.local",
                                      password: SecureRandom.hex(16), guest: true)

  def member
    @member ||= User.create!(email_address: "member_#{SecureRandom.hex(4)}@brgen.no",
                             password: SecureRandom.hex(16), guest: false,
                             email_verified_at: Time.current)
  end

  test "approves on timeout without raising" do
    post = Post.new(title: "Hello", content: "Neighborhood meetup Saturday", user: member)
    service = PostModeration.new(post)
    service.define_singleton_method(:moderate_sync) { raise Timeout::Error }

    assert service.approve?
  end

  # The heuristic runs before the LLM and needs no key, which is the whole point:
  # production has no key, so for three weeks approve? was `true` unconditionally.
  test "rejects a link from a guest even with no moderation key configured" do
    SPAM.each do |body|
      post = Post.new(title: body.lines.first.to_s.strip, content: body, user: guest)
      verdict = PostModeration.new(post).decide

      refute verdict.approved, "should have rejected: #{body[0, 40]}"
      assert_equal :unverified_author_spam_signals, verdict.reason
    end
  end

  # The family this deliberately does not catch, pinned so the gap is a fact in
  # the suite rather than a thing someone assumes was covered.
  test "does not catch the one-sentence foreign-language price template" do
    post = Post.new(title: "Szia, meg akartam tudni az árát.",
                    content: "Szia, meg akartam tudni az árát.", user: guest)

    assert PostModeration.new(post).decide.approved,
           "if this starts failing the heuristics grew a language check — update the comment in PostModeration"
  end

  test "rejects a bare hostname, not only a full URL" do
    post = Post.new(title: "Hi,", content: "check out cheap-proxies.top for details", user: guest)

    refute PostModeration.new(post).decide.approved
  end

  # Anonymous posting is a feature. A guest writing an ordinary post must still
  # get through, or the fix is worse than the spam.
  test "allows a guest posting without a link" do
    post = Post.new(title: "Noen som vet når biblioteket åpner?",
                    content: "Skulle innom i dag, men det var stengt.", user: guest)

    assert PostModeration.new(post).decide.approved
  end

  # And a verified member may post links — that is the difference the rule turns on.
  test "allows a verified member to post a link" do
    post = Post.new(title: "Konsert på lørdag",
                    content: "Billetter her: https://ticketmaster.no/event/123", user: member)

    assert PostModeration.new(post).decide.approved
  end

  # Every one of the ten short Live posts has title == content, and none is spam.
  # An earlier version of the sweep keyed on that and would have deleted all ten.
  test "allows a member post whose title and content are identical" do
    text = "Gratis kaffe på uteservering ved Torget — ta med egen kopp."
    post = Post.new(title: text, content: text, user: member)

    assert PostModeration.new(post).decide.approved
  end
end
