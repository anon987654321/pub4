# frozen_string_literal: true

Pundit.policy_class = Shared::RecordPolicy if defined?(Shared::RecordPolicy)
