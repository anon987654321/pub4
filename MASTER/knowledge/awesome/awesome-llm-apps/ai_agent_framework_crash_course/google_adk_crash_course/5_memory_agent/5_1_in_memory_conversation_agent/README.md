# lib/master/memory.rb
# Simple in‑memory conversation buffer.
# Supports append, history and clear while protecting against
# unbounded growth and race conditions.
# Interface unchanged for callers.

class Master::Memory
  DEFAULT_MAX_SIZE = 10_000 # arbitrary safety ceiling

  def initialize(max_size: DEFAULT_MAX_SIZE)
    @max_size = max_size
    @store    = []            # [{role:, content:}, …]
    @mutex    = Mutex.new
    freeze
  end

  # Append a new message to the conversation.
  # Returns self for chaining.
  def append(role, content)
    raise ArgumentError, "role required"  unless role
    raise ArgumentError, "content required" unless content

    @mutex.synchronize do
      @store << { role: role, content: content }
      @store.shift while @store.size > @max_size
    end
    self
  end

  # Retrieve the full history as a shallow‑copied array of hashes.
  def history
    @mutex.synchronize { @store.dup }
  end

  # Clear the buffer (useful for teardown).
  # Returns self for chaining.
  def clear
    @mutex.synchronize { @store.clear }
    self
  end
end