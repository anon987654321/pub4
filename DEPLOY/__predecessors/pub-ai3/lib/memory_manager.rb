# encoding: utf-8
# Memory management for session data

class MemoryManager
  def initialize
    @memory = {}
  end

  def store(user_id, key, value)
    @memory[user_id] ||= {}
    @memory[user_id][key] = value
  end

  def retrieve(user_id, key)
    @memory[user_id] ||= {}
    @memory[user_id][key]
  end

  def clear(user_id)
    @memory[user_id] = {}
  end

  def get_context(user_id)
    @memory[user_id] || {}
  end
end
