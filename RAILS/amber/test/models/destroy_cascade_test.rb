# frozen_string_literal: true

require "test_helper"
require "shared/destroy_cascade_examples"

# The reflection sweep is engine-owned and runs against this app's own models —
# see Shared::DestroyCascadeExamples for why strict loading and a destroy
# cascade cannot coexist. brgen's copy adds the behavioural half on top.
class DestroyCascadeTest < ActiveSupport::TestCase
  include Shared::DestroyCascadeExamples
end
