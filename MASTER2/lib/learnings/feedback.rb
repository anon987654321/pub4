# frozen_string_literal: true

require "digest"

module Learnings
  class Feedback
    TOKEN_SALT = "learnings-feedback".freeze

    def self.for_training(training_id)
      ::Feedback.includes(:user, :training).where(training_id: training_id)
    end

    def initialize(feedback)
      @feedback = feedback
    end

    def anonymized_token
      raw = "#{TOKEN_SALT}:#{@feedback.id}:#{@feedback.user_id}"
      Digest::SHA256.hexdigest(raw)
    end

    def submit_to_analytics
      return unless @feedback
      return unless @feedback.user_id

      payload = build_payload

      begin
        Analytics.track(payload)
      rescue Analytics::Error => e
        Rails.logger.warn(
          "Analytics track failed for feedback_id=#{@feedback.id}: #{e.class}: #{e.message}"
        )
        nil
      end
    end

    def build_payload
      user = @feedback.user
      training = @feedback.training

      {
        event: "training_feedback_submitted",
        user_id: user&.id,
        training_id: training&.id,
        training_title: training&.title,
        rating: @feedback.rating,
        comment: @feedback.comment.to_s,
        token: anonymized_token
      }
    end

    def instructor_name
      training = @feedback.training
      instructor = training&.instructor
      instructor&.full_name
    end

    private

    attr_reader :feedback
  end
end