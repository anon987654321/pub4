# frozen_string_literal: true

# model_contract: no-validations-ok — a tagging is an occurrence, not a fact:
# hashtag_test.rb tags one post with one hashtag twice on purpose, because
# trending counts rows. Uniqueness here would be wrong, not missing.
class Tagging < ApplicationRecord
  belongs_to :taggable, polymorphic: true
  belongs_to :hashtag
end
