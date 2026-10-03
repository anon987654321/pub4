# frozen_string_literal: true

# Email verification. A registered account must confirm its address before it can
# post under its identity — closes the "register with anyone's email and post at
# once" impersonation hole. Anonymous guests are unaffected (they never claim an
# identity). Nullable so existing accounts are treated as already-trusted rather
# than locked out on deploy; backfilled to verified in the same migration.
class AddEmailVerificationToUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :email_verified_at, :datetime unless column_exists?(:users, :email_verified_at)
    add_column :users, :email_verification_token, :string unless column_exists?(:users, :email_verification_token)
    add_index :users, :email_verification_token, unique: true unless index_exists?(:users, :email_verification_token)

    # Existing real accounts predate the gate — grandfather them in so nobody is
    # locked out. Guests are irrelevant (they never post under an identity).
    say_with_time "grandfathering existing accounts as verified" do
      execute("UPDATE users SET email_verified_at = CURRENT_TIMESTAMP WHERE email_verified_at IS NULL AND guest = 0")
    end
  end

  def down
    remove_column :users, :email_verified_at
    remove_column :users, :email_verification_token
  end
end
