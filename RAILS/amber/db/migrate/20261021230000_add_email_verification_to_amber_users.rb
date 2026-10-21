# frozen_string_literal: true

# Match Brgen's account-verification boundary. Existing accounts are grandfathered
# verified so deploying the gate never locks out people who already use Amber.
class AddEmailVerificationToAmberUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :email_verified_at, :datetime unless column_exists?(:users, :email_verified_at)
    add_column :users, :email_verification_token, :string unless column_exists?(:users, :email_verification_token)
    add_index :users, :email_verification_token, unique: true unless index_exists?(:users, :email_verification_token)

    say_with_time "grandfathering existing Amber accounts as verified" do
      execute("UPDATE users SET email_verified_at = CURRENT_TIMESTAMP WHERE email_verified_at IS NULL AND guest = 0")
    end
  end

  def down
    remove_index :users, :email_verification_token if index_exists?(:users, :email_verification_token)
    remove_column :users, :email_verification_token if column_exists?(:users, :email_verification_token)
    remove_column :users, :email_verified_at if column_exists?(:users, :email_verified_at)
  end
end
