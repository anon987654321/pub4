# frozen_string_literal: true

class User
  module DatingAssociations
    extend ActiveSupport::Concern

    included do
      has_many :dating_dislikes, class_name: "Dating::Dislike", foreign_key: :disliker_id, dependent: :destroy,
               inverse_of: :disliker
      has_many :dating_likes, class_name: "Dating::Like", foreign_key: :liker_id, dependent: :destroy,
               inverse_of: :liker
      has_many :dating_matches_as_initiator, class_name: "Dating::Match", foreign_key: :initiator_id,
               dependent: :destroy, inverse_of: :initiator
      has_many :dating_matches_as_receiver, class_name: "Dating::Match", foreign_key: :receiver_id, dependent: :destroy,
               inverse_of: :receiver
      has_one :dating_profile, class_name: "Dating::Profile", dependent: :destroy
    end
  end
end
