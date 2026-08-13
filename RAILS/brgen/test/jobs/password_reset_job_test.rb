# frozen_string_literal: true

require 'ostruct'
require 'minitest/mock'
require 'test_helper'

class PasswordResetJobTest < ActiveSupport::TestCase
  test 'performs password reset mailer synchronously' do
    user = OpenStruct.new(id: 7, email_address: 'user@example.com')
    delivered = false
    mail = Object.new
    mail.define_singleton_method(:deliver_now) { delivered = true }

    User.stub(:find_by, user) do
      PasswordsMailer.stub(:reset, mail) do
        Shared::PasswordResetJob.perform_now(user.id)
      end
    end

    assert delivered
  end

  # perform_later has to send the mail, not enqueue it. Nothing on vm23 runs the
  # queue -- 1670 jobs enqueued, 0 finished, no registered process -- so an
  # enqueued password reset is a password reset that never arrives, under a page
  # that says one was sent.
  test 'perform_later sends immediately rather than enqueuing' do
    user = OpenStruct.new(id: 7, email_address: 'user@example.com')
    delivered = false
    mail = Object.new
    mail.define_singleton_method(:deliver_now) { delivered = true }

    User.stub(:find_by, user) do
      PasswordsMailer.stub(:reset, mail) do
        Shared::PasswordResetJob.perform_later(user.id)
      end
    end

    assert delivered, 'perform_later did not deliver -- the job is back on a queue nobody runs'
  end

  # raise_delivery_errors is true in production, and inline execution puts the
  # mailer inside the request. An SMTP failure must not 500 the reset form: that
  # breaks the page and confirms to whoever is probing that the address exists.
  test 'a delivery failure is logged, not raised at the controller' do
    user = OpenStruct.new(id: 7, email_address: 'user@example.com')
    mail = Object.new
    mail.define_singleton_method(:deliver_now) { raise Net::SMTPServerBusy, 'nope' }

    assert_nothing_raised do
      User.stub(:find_by, user) do
        PasswordsMailer.stub(:reset, mail) do
          Shared::PasswordResetJob.perform_later(user.id)
        end
      end
    end
  end
end
