# frozen_string_literal: true

# model_contract: no-validations-ok — the Rails 8 authentication generator's
# session row. What it promises is a user_id the database already requires;
# credentials are validated on User.
class Session < ApplicationRecord
  belongs_to :user
end
