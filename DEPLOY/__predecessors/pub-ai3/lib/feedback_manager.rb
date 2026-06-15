# encoding: utf-8
# Feedback manager for handling user feedback and improving services

require_relative "error_handling"

class FeedbackManager
  include ErrorHandling

  def initialize(weaviate_client)
    @client = weaviate_client
  end

  def record_feedback(user_id, query, feedback)
    with_error_handling do
      feedback_data = {
        "user_id": user_id,
        "query": query,
        "feedback": feedback
      }
      @client.data_object.create(feedback_data, "UserFeedback")
      update_model_based_on_feedback(feedback_data)
    end
  end

  def update_model_based_on_feedback(feedback_data)
    puts "Feedback received: #{feedback_data}"
  end
end
