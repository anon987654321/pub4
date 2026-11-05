# frozen_string_literal: true

# A line or two the person writes about themselves, shown under their name on
# the profile. User::BIO_LENGTH holds it short.
class AddBioToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :bio, :text
  end
end
