# frozen_string_literal: true

# The language an account chose on its account page. Null means "follow the
# site", which is the domain's language as before.
class AddLocaleToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :locale, :string
  end
end
