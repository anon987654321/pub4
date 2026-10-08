# frozen_string_literal: true

require "test_helper"

class Marketplace::QuestionTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @category = Marketplace::Category.create!(name: "Kategori #{SecureRandom.hex(4)}")
    @seller = User.strict_loading(false).create!(
      email_address: "q_seller@brgen.no", password: "password123", city: @city
    )
    @asker = User.strict_loading(false).create!(email_address: "q_asker@brgen.no", password: "password123", city: @city)
    @listing = ActsAsTenant.with_tenant(@city) do
      Marketplace::Listing.create!(
        category: @category, user: @seller, title: "Kajakk", price_cents: 4_000_00, currency: "NOK"
      )
    end
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  test "a question needs a body, and both halves are bounded" do
    blank = Marketplace::Question.new(listing: @listing, user: @asker, body: "")
    long = Marketplace::Question.new(listing: @listing, user: @asker, body: "x" * 1_001, answer: "y" * 2_001)

    assert_not blank.valid?
    assert blank.errors.added?(:body, :blank)
    assert_not long.valid?
    assert long.errors.added?(:body, :too_long, count: 1_000)
    assert long.errors.added?(:answer, :too_long, count: 2_000)
  end

  test "asking on a freshly found listing notifies its seller" do
    listing = Marketplace::Listing.find(@listing.id)
    question = Marketplace::Question.new(listing: listing, user: @asker, body: "Er den tett?")

    assert_difference -> { Notification.where(user_id: @seller.id).count }, 1 do
      assert question.ask!
    end
    assert_includes Marketplace::Question.unanswered, question
  end

  test "a refused question is not saved and notifies nobody" do
    assert_no_difference -> { Notification.count } do
      assert_not Marketplace::Question.new(listing: @listing, user: @asker, body: "").ask!
    end
  end

  test "answering a freshly found question records who answered and tells the asker" do
    id = Marketplace::Question.create!(listing: @listing, user: @asker, body: "Hvor lang?").id
    question = Marketplace::Question.find(id)

    assert_difference -> { Notification.where(user_id: @asker.id).count }, 1 do
      assert question.answer!("Fire meter", by: @seller)
    end
    question.reload
    assert question.answered?
    assert_equal @seller.id, question.answered_by_id
    assert_includes Marketplace::Question.answered, question
  end

  test "only the listing's seller may answer" do
    id = Marketplace::Question.create!(listing: @listing, user: @asker, body: "Pris?").id
    question = Marketplace::Question.find(id)

    assert question.answerable_by?(@seller)
    assert_not question.answerable_by?(@asker)
    assert_not question.answerable_by?(nil)
  end
end
