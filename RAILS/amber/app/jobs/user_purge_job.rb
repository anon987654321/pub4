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
  # the due deletion marker for the next scheduled attempt. Every destroy here
  # loads with strict_loading(false): destroy callbacks read the records they
  # point at, which strict loading refuses, and one refusal rolled back the
  # whole erasure (brgen's job hit the same on Vote#votable).
  DESTROY = [
    { model: "Profile", key: :user_id },
    { model: "CreatorProfile", key: :user_id },
    { model: "PrivacySetting", key: :user_id },
    { model: "ExternalIdentity", key: :user_id },
    { model: "IdentityVerification", key: :user_id },
    { model: "ConsentEvent", key: :user_id },
    { model: "AccountMerge", key: :user_id },
    { model: "AccountMerge", key: :guest_user_id },
    { model: "Notification", key: :user_id },
    { model: "Notification", key: :actor_id },
    { model: "Shared::OutboundClick", key: :user_id },
    { model: "Reaction", key: :user_id },
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
    { model: "Session", key: :user_id },
  ].freeze

  # Public posts and comments remain on the anonymised user so conversations
  # do not disappear. Posts lose references to private wardrobe objects before
  # those objects are removed. Comments about a deleted private item/outfit do
  # not survive as dangling polymorphic references.
  def perform
    return unless User.column_names.include?("deletion_scheduled_at")

    failures = []
    User.where.not(deletion_scheduled_at: nil)
        .where("deletion_scheduled_at <= ?", Time.current)
        .find_each do |user|
      begin
        erase!(user)
      rescue StandardError => error
        # Keep this user's deletion marker so the next run retries it, but do
        # not let one corrupt record prevent unrelated due accounts being erased.
        Rails.logger.error("[privacy] Amber erasure failed user_id=#{user.id} error=#{error.class}")
        failures << [user.id, error.class.name]
      end
    end
    return if failures.empty?

    raise "Amber account erasure failures: #{failures.map { |id, kind| "#{id}=#{kind}" }.join(", ")}"
  end

  private

  def erase!(user)
    former_email = user.try(:email_address)

    user_id = user.id
    ActiveRecord::Base.transaction do
      item_ids = Item.where(user_id:).select(:id)
      outfit_ids = Outfit.where(user_id:).select(:id)
      message_ids = Message.where(sender_id: user_id).or(Message.where(recipient_id: user_id)).select(:id)
      detach_deleted_private_content(item_ids:, outfit_ids:, message_ids:)

      DESTROY.each do |row|
        model = resolve!(row.fetch(:model))
        destroy_each(model.where(row.fetch(:key) => user_id))
      end

      nullify_review_cases(user)
      erase_email_subscription(former_email)
      anonymise(user)
    end
  end

  def detach_deleted_private_content(item_ids:, outfit_ids:, message_ids:)
    # Foreign-key inventory: items/outfits are referenced by content and
    # derived suggestions outside the deleted user's own associations.
    Post.where(item_id: item_ids).update_all(item_id: nil)
    Post.where(outfit_id: outfit_ids).update_all(outfit_id: nil)
    destroy_each(CreatorWardrobeItem.where(item_id: item_ids))
    destroy_each(WardrobeItem.where(item_id: item_ids))
    destroy_each(Recommendation.where(item_id: item_ids).or(Recommendation.where(outfit_id: outfit_ids)))
    # Polymorphic activity has no database foreign keys, so every other user's
    # reaction, notification or vote on a private object needs explicit removal.
    reaction_model = canonical_reaction_model
    notification_model = canonical_notification_model
    if reaction_model&.table_exists?
      destroy_each(reaction_model.where(reactable_type: "Item", reactable_id: item_ids))
      destroy_each(reaction_model.where(reactable_type: "Outfit", reactable_id: outfit_ids))
    end
    private_comment_ids = Comment.where(commentable_type: "Item", commentable_id: item_ids)
                                  .or(Comment.where(commentable_type: "Outfit", commentable_id: outfit_ids))
                                  .select(:id)
    if reaction_model&.table_exists?
      destroy_each(reaction_model.where(reactable_type: "Comment", reactable_id: private_comment_ids))
      destroy_each(reaction_model.where(reactable_type: "Message", reactable_id: message_ids))
    end
    if notification_model&.table_exists?
      destroy_each(notification_model.where(notifiable_type: "Item", notifiable_id: item_ids))
      destroy_each(notification_model.where(notifiable_type: "Outfit", notifiable_id: outfit_ids))
      destroy_each(notification_model.where(notifiable_type: "Comment", notifiable_id: private_comment_ids))
      destroy_each(notification_model.where(notifiable_type: "Message", notifiable_id: message_ids))
    end
    if defined?(Shared::OutboundClick) && Shared::OutboundClick.table_exists?
      destroy_each(Shared::OutboundClick.where(subject_type: "Comment", subject_id: private_comment_ids))
      destroy_each(Shared::OutboundClick.where(subject_type: "Message", subject_id: message_ids))
    end
    destroy_each(Vote.where(votable_type: "Item", votable_id: item_ids))
    destroy_each(Vote.where(votable_type: "Outfit", votable_id: outfit_ids))
    destroy_each(Vote.where(votable_type: "Comment", votable_id: private_comment_ids))
    destroy_each(Vote.where(votable_type: "Message", votable_id: message_ids))
    # These are per-user records, but Item declares them as has_one even
    # though the schema allows multiple users to reference the same item.
    # Explicitly remove every user's rows before erasing the target item.
    destroy_each(DeclutterReview.where(item_id: item_ids))
    destroy_each(DeclutterOutcome.where(item_id: item_ids))
    destroy_each(DeclutterChallenge.where(item_id: item_ids))
    DeclutterChallenge.where(outfit_id: outfit_ids).update_all(outfit_id: nil)
    destroy_each(Comment.where(commentable_type: "Item", commentable_id: item_ids))
    destroy_each(Comment.where(commentable_type: "Outfit", commentable_id: outfit_ids))
    if defined?(Shared::ReviewCase) && Shared::ReviewCase.table_exists?
      destroy_each(Shared::ReviewCase.where(reviewable_type: "Item", reviewable_id: item_ids))
      destroy_each(Shared::ReviewCase.where(reviewable_type: "Outfit", reviewable_id: outfit_ids))
    end
    if defined?(Shared::OutboundClick) && Shared::OutboundClick.table_exists?
      destroy_each(Shared::OutboundClick.where(subject_type: "Item", subject_id: item_ids))
      destroy_each(Shared::OutboundClick.where(subject_type: "Outfit", subject_id: outfit_ids))
    end
  end

  # One row at a time so callbacks run, loaded without strict loading because
  # those callbacks read the records the rows point at.
  def destroy_each(scope)
    scope.strict_loading(false).find_each(&:destroy!)
  end

  def nullify_review_cases(user)
    return unless defined?(Shared::ReviewCase) && Shared::ReviewCase.table_exists?

    destroy_each(Shared::ReviewCase.where(reporter_id: user.id))
    Shared::ReviewCase.where(reviewer_id: user.id).update_all(reviewer_id: nil)
  end

  def erase_email_subscription(email)
    return if email.blank?
    return unless defined?(::EmailSubscription) && ::EmailSubscription.table_exists?

    destroy_each(::EmailSubscription.where(email:))
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

  def canonical_reaction_model
    return ::Reaction if defined?(::Reaction)
    return Shared::Reaction if defined?(Shared::Reaction)
  end

  def canonical_notification_model
    return ::Notification if defined?(::Notification)
    return Shared::Notification if defined?(Shared::Notification)
  end

  def resolve!(name)
    model = case name
            when "Reaction" then canonical_reaction_model
            when "Notification" then canonical_notification_model
            else name.safe_constantize
            end
    raise "erasure model unavailable: #{name}" unless model
    raise "erasure table unavailable: #{name}" unless model.respond_to?(:table_exists?) && model.table_exists?

    model
  end
end
