# frozen_string_literal: true

# model_contract: no-validations-ok — nothing reads or writes this model. The
# table exists and the class does not; validating a row nobody creates promises
# nothing. See TODO.md.
class Stream < ApplicationRecord
  belongs_to :user
  belongs_to :post
end
