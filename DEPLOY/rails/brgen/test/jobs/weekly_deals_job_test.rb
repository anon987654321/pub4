# frozen_string_literal: true

require 'ostruct'
require 'test_helper'

class WeeklyDealsJobTest < ActiveSupport::TestCase
  test 'performs weekly deals mailer for marketing subscribers' do
    subscription = OpenStruct.new(email: 'news@example.com', city: 'bergen', token: 'abc123')
    relation = Object.new
    relation.define_singleton_method(:find_each) { |&block| block.call(subscription) }

    delivered = false
    mail = Object.new
    mail.define_singleton_method(:deliver_now) { delivered = true }

    NewsletterMailer.stub(:weekly_deals, mail) do
      EmailSubscription.stub(:marketing_opted_in, relation) do
        WeeklyDealsJob.perform_now
      end
    end

    assert delivered
  end
end