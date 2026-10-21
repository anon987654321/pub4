# frozen_string_literal: true

# GDPR Art. 17 erasure for Amber. Users are anonymised in place so public
# posts and comments keep their threads, but private wardrobe data, identity
# credentials and inbox messages are destroyed. Every private relation is
# explicit because update_columns on the user does not run dependent callbacks.
class UserPurgeJob < ApplicationJob
  queue_as :bulk
  limits_concurrency to: 1, key: "user-purge", duration: 1.hour, on_conflict: :discard

  # Destroy actual model rows one at a time where callbacks purge attachments or
  # remove dependent records. The model and table are both required: a missing
  # migration halts the transaction before the account is anonymised, leaving
  # the due deletion marker for the next scheduled attempt.
  DESTROY = [
    { model: "Profile", key: :user_id },
    { model: "CreatorProfile", key: :user_id },
    { model: "PrivacySetting", key: :user_id },
    { model: "ExternalIdentity", key: :user_id },
    { model: "IdentityVerification", key: :user_id },
    { model: "ConsentEvent", key: :user_id },
    { model: "AccountMerge", key: :user_id },
    { model: "AccountMerge", key: :guest_user_id },
    { model: "Shared::Notification", key: :user_id },
    { model: "Shared::Notification", key: :actor_id },
    { model: "Shared::Reaction", key: :user_id },
    { model: "Vote", key: :user_id },
    { model: "Follow", key: :follower_id },
    { model: "Follow", key: :followee_id },
    { model: "Connection", key: :requester_id },
    { model: "Connection", key: :addressee_id },
    { model: "Message", key: :sender_id },
    { model: "Message", key: :recipient_id },
    { model: "LiveStream", key: :user_id },
    { model: "WearLog", key: :user_id },
    { model: "DeclutterReview", key: :user_id },
    { model: "DeclutterChallenge", key: :user_id },
    { model: "DeclutterOutcome", key: :user_id },
    { model: "Recommendation", key: :user_id },
    { model: "PackingList", key: :user_id },
    { model: "PlannedOutfit", key: :user_id },
    { model: "StylePreference", key: :user_id },
    { model: "Outfit", key: :user_id },
    { model: "Item", key: :user_id },
    { model: "WardrobeItem", key: :user_id },
    { model: "Session", key: :user_id }
  ].freeze

  # Public posts and comments remain on the anonymised user so conversations
  # do not disappear. Posts lose references to private wardrobe objects before
  # those objects are removed. Comments about a deleted private item/outfit do
  # not survive as dangling polymorphic references.
  def perform
    return unless User.column_names.include?("deletion_scheduled_at")

    User.where.not(deletion_scheduled_at: nil)
        .where("deletion_scheduled_at <= ?", Time.current)
        .find_each { |user| erase!(user) }
  end

  private

  def erase!(user)
    former_email = user.try(:email_address)

    ActiveRecord::Base.transaction do
      item_ids = Item.where(user_id: user.id).select(:id)
      outfit_ids = Outfit.where(user_id: user.id).select(:id)

      Post.where(item_id: item_ids).update_all(item_id: nil)
      Post.where(outfit_id: outfit_ids).update_all(outfit_id: nil)
      Comment.where(commentable_type: "Item", commentable_id: item_ids).find_each(&:destroy!)
      Comment.where(commentable_type: "Outfit", commentable_id: outfit_ids).find_each(&:destroy!)

      DESTROY.each do |row|
        model = resolve!(row.fetch(:model))
        model.where(row.fetch(:key) => user.id).find_each(&:destroy!)
      end

      nullify_review_cases(user)
      erase_email_subscription(former_email)
      anonymise(user)
      user.sessions.delete_all
    end
  end

  def nullify_review_cases(user)
    return unless defined?(Shared::ReviewCase) && Shared::ReviewCase.table_exists?

    Shared::ReviewCase.where(reporter_id: user.id).find_each(&:destroy!)
    Shared::ReviewCase.where(reviewer_id: user.id).update_all(reviewer_id: nil)
  end

  def erase_email_subscription(email)
    return if email.blank?
    return unless defined?(::EmailSubscription) && ::EmailSubscription.table_exists?

    ::EmailSubscription.where(email: email).find_each(&:destroy!)
  end

  def anonymise(user)
    attrs = {
      deleted_at: Time.current,
      deletion_scheduled_at: nil,
      email_address: "purged-#{user.id}@deleted.invalid",
      password_digest: BCrypt::Password.create(SecureRandom.hex(24), cost: BCrypt::Engine::MIN_COST),
      email_verified_at: nil,
      email_verification_token: nil,
      magic_link_token: nil,
      magic_link_expires_at: nil,
      remember_token: nil,
      remember_token_expires_at: nil,
      otp_secret: nil,
      two_factor_enabled: false,
      updated_at: Time.current
    }
    attrs.select! { |column, _value| user.has_attribute?(column) }
    user.update_columns(attrs)
  end

  def resolve!(name)
    model = name.safe_constantize
    raise "erasure model unavailable: #{name}" unless model
    raise "erasure table unavailable: #{name}" unless model.respond_to?(:table_exists?) && model.table_exists?

    model
  end
end
