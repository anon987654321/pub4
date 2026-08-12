# frozen_string_literal: true

require "test_helper"
require "shared/importmap_external_hosts_examples"

# Assertions live in the engine: all three apps eval the same
# importmap_baseline.rb, so a CDN pin lands in all three at once.
class ImportmapExternalHostsTest < ActiveSupport::TestCase
  include Shared::ImportmapExternalHostsExamples
end
