# frozen_string_literal: true

require "test_helper"
require "shared/user_auth_examples"

# The shared auth contract, asserted against this app's own User. The
# assertions live in the engine because every app inherits the same email and
# password columns from the same migrations; the model does not, so the test
# case does.
class UserTest < ActiveSupport::TestCase
  include Shared::UserAuthExamples

  test "master bot is a stable reserved participant" do
    master = User.master_bot

    assert master.bot?
    assert master.guest?
    assert master.master_bot?
    assert_equal "MASTER", master.display_name
    assert_equal master.id, User.master_bot.id
  end
end
