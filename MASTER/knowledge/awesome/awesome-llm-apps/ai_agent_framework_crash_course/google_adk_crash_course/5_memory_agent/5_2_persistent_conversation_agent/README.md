# frozen_string_literal: true

# config/initializers/persistent_conversation.rb
#
# Boot the Master framework with an ActiveRecord‑backed memory store.
# The built‑in ActiveRecord adapter writes conversation state to the
# tables created by `rails generate master:install`.  This gives agents
# true persistence across process restarts and across multiple workers.
#
# Customize the adapter or model per deployment by adjusting the
# configuration block below.

require "master"

Master.configure do |c|
  # Store all conversation turns in the `master_memories` table.
  # Other adapters (e.g. :redis, :file) are available; see
  # lib/master/memory.rb for the complete list.
  c.memory_adapter = :active_record

  # Global default LLM; individual agents may override this with
  # `c.model = "provider/model"` in their own configuration.
  c.default_model = "deepseek-ai/deepseek-v3"
end