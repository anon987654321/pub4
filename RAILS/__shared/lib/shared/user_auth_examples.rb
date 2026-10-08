# frozen_string_literal: true

module Shared
  # The email/password half of User, which every app gets from the same shared
  # auth migrations and Shared::Authentication rather than from its own model.
  # Each app owns the rest of its User — amber's carries the wardrobe
  # associations, brgen's the city tenancy — so the model stays per-app and only
  # the contract is shared:
  #
  #   class UserTest < ActiveSupport::TestCase
  #     include Shared::UserAuthExamples
  #   end
  #
  # Asserted through the I18n key, not the English sentence. These apps default
  # to nb; the literals only ever matched because rails-i18n was missing, so the
  # tests were pinned to the absence of a translation.
  module UserAuthExamples
    def self.included(base)
      base.class_eval do
        test "requires email address" do
          user = User.new(password: "password")

          assert_not user.valid?
          assert_includes user.errors[:email_address], I18n.t("errors.messages.blank")
        end

        test "requires unique email address" do
          User.strict_loading(false).create!(email_address: "dup@example.com", password: "password")
          duplicate = User.new(email_address: "dup@example.com", password: "password")

          assert_not duplicate.valid?
          assert_includes duplicate.errors[:email_address], I18n.t("errors.messages.taken")
        end
      end
    end
  end
end
