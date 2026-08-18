# frozen_string_literal: true

# A question and the answer someone gave it.
#
# The current shape of this category is Hinge, not Tinder: you like a specific
# answer and say something about it, rather than swiping on a whole person. A
# like that carries a sentence is a different product from one that carries
# nothing, and prompts are what give it something to point at.
class Dating::Prompt < ApplicationRecord
  belongs_to :profile, class_name: "Dating::Profile"
  has_many :likes, class_name: "Dating::Like", foreign_key: :dating_prompt_id, dependent: :nullify

  # A fixed list, deliberately. Free-text questions become a second bio, and the
  # point of a prompt is that everyone answers the same odd question differently.
  QUESTIONS = [
    "dating.prompts.q_sunday",
    "dating.prompts.q_bergen",
    "dating.prompts.q_unpopular",
    "dating.prompts.q_teach",
    "dating.prompts.q_never",
    "dating.prompts.q_meal",
    "dating.prompts.q_song",
    "dating.prompts.q_weekend",
  ].freeze

  MAX_PER_PROFILE = 3

  validates :question, presence: true, inclusion: { in: QUESTIONS }
  validates :answer, presence: true, length: { maximum: 255 }
  validate :within_profile_limit, on: :create

  scope :ordered, -> { order(:position, :id) }

  # `city:` is passed for every question, not just the one that reads it: I18n
  # ignores interpolation values a string does not name, and gating it on which
  # key happens to carry %{city} today is a trap for whoever writes the ninth
  # question.
  def question_text = I18n.t(question, city: Current.city_name)

  private

  # Three, because a profile that answers eight is a bio in disguise and the
  # deck stops being skimmable.
  def within_profile_limit
    return if Dating::Prompt.where(profile_id: profile_id).count < MAX_PER_PROFILE

    errors.add(:base, :too_many_prompts)
  end
end
