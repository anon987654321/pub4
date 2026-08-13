# frozen_string_literal: true

require 'ostruct'
require 'minitest/mock'
require 'test_helper'

class EmailSubscriptionConfirmationJobTest < ActiveSupport::TestCase
  test 'performs subscription confirmation mailer synchronously' do
    subscription = OpenStruct.new(id: 42, email: 'news@example.com', token: 'abc123')
    delivered = false
    mail = Object.new
    mail.define_singleton_method(:deliver_now) { delivered = true }

    EmailSubscription.stub(:find_by, subscription) do
      EmailSubscriptionMailer.stub(:confirm, mail) do
        EmailSubscriptionConfirmationJob.perform_now(subscription.id)
      end
    end

    assert delivered
  end
end
