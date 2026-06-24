# frozen_string_literal: true

require 'ostruct'
require 'test_helper'

class DailyDigestJobTest < ActiveSupport::TestCase
  test 'performs daily digest mailer for marketing subscribers' do
    subscription = OpenStruct.new(email: 'news@example.com', city: 'bergen', token: 'abc123')
    relation = Object.new
    relation.define_singleton_method(:find_each) { |&block| block.call(subscription) }

    mail = Minitest::Mock.new
    mail.expect(:deliver_now, true)

    NewsletterMailer.stub(:daily_digest, mail) do
      EmailSubscription.stub(:marketing_opted_in, relation) do
        DailyDigestJob.perform_now
      end
    end

    assert mail.verify
  end
end
