# frozen_string_literal: true

require "minitest/autorun"
require "active_support/core_ext/string/inflections"
require_relative "../../app/services/shared/domain_event"
require_relative "../../app/services/shared/event_emitter"

class SharedDomainEventTest < Minitest::Test
  def test_action_to_event_name_maps_dotted_actions
    assert_equal "PostCreated", Shared::DomainEvent.send(:action_to_event_name, "post.created")
  end
end
