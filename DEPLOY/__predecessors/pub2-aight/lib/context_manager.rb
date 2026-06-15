# encoding: utf-8
# Manages user-specific context for maintaining conversation state

class ContextManager
  def initialize
    @contexts = {}
  end

  def update_context(user_id:, text:)
    @contexts[user_id] ||= []
    @contexts[user_id] << text
    trim_context(user_id) if @contexts[user_id].join(" ").length > 4096
  end

  def get_context(user_id:)
    @contexts[user_id] || []
  end

  def trim_context(user_id)
    context_text = @contexts[user_id].join(" ")
    while context_text.length > 4096
      @contexts[user_id].shift
      context_text = @contexts[user_id].join(" ")
    end
  end
end
