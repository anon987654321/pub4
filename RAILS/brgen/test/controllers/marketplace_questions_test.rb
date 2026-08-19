# frozen_string_literal: true

require "test_helper"

# Every buyer used to ask the same thing in a private offer thread, the seller
# answered it once per buyer, and the answer left with them.
class MarketplaceQuestionsTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @seller = create_user("mq_seller")
    @buyer = create_user("mq_buyer")
    @other = create_user("mq_other")
    ActsAsTenant.current_tenant = @city
    category = Marketplace::Category.create!(name: "Sykler", slug: "sykler-#{SecureRandom.hex(4)}")
    @listing = Marketplace::Listing.create!(user: @seller, category: category,
                                            title: "Sykkel #{SecureRandom.hex(3)}", price_cents: 250_000)
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def create_user(name)
    User.strict_loading(false).create!(
      email_address: "#{name}@brgen.no", password: "password123", username: name, guest: false
    )
  end

  def sign_in_as(user)
    host! "markedsplass.brgen.no"
    post main_app.session_path(host: "brgen.no"), params: { email_address: user.email_address, password: "password123" }
    host! "markedsplass.brgen.no"
  end

  test "a question is public on the listing, and the seller hears about it" do
    sign_in_as(@buyer)

    assert_difference -> { Marketplace::Question.count }, 1 do
      post marketplace.listing_questions_path(@listing), params: { marketplace_question: { body: "Er den fortsatt ledig?" } }
    end
    question = Marketplace::Question.order(:created_at).last
    assert_equal @buyer.id, question.user_id
    assert_not_predicate question, :answered?
    assert Notification.where(user_id: @seller.id, kind: "alert").exists?

    get marketplace.listing_path(@listing)
    assert_includes response.body, "Er den fortsatt ledig?"
  end

  test "only the seller answers" do
    question = @listing.questions.create!(user: @buyer, body: "Fungerer girene?")
    sign_in_as(@other)

    patch marketplace.listing_question_path(@listing, question), params: { marketplace_question: { answer: "Nei" } }
    assert_response :forbidden
    assert_not_predicate question.reload, :answered?

    sign_in_as(@seller)
    patch marketplace.listing_question_path(@listing, question), params: { marketplace_question: { answer: "Ja, nettopp overhalt" } }
    assert_predicate question.reload, :answered?
    assert_equal @seller.id, question.answered_by_id
    assert Notification.where(user_id: @buyer.id, kind: "alert").exists?
  end

  # An answered question is what a reader came for; an unanswered one is a
  # question they may have too.
  test "answered questions come first" do
    old_answered = @listing.questions.create!(user: @buyer, body: "Farge?", answer: "Blå",
                                              answered_by: @seller, answered_at: 2.days.ago)
    fresh_unanswered = @listing.questions.create!(user: @other, body: "Kvittering?")

    assert_equal [ old_answered.id, fresh_unanswered.id ], @listing.questions.for_display.map(&:id)
  end
end
