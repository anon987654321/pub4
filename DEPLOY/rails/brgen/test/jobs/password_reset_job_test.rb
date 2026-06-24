# frozen_string_literal: true

require "ostruct"
require "test_helper"

class PasswordResetJobTest < ActiveSupport::TestCase
  test "performs password reset mailer synchronously" do
    user = OpenStruct.new(id: 7, email_address: "user@example.com")
    mail = Minitest::Mock.new
    mail.expect(:deliver_now, true)

    User.stub(:find_by, user) do
      PasswordsMailer.stub(:reset, mail) do
        Shared::PasswordResetJob.perform_now(user.id)
      end
    end

    mail.verify
  end
end
