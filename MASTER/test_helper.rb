# frozen_string_literal: true

# Tests that sit one level below MASTER/ reach the suite helper through this
# path. It delegates so they get the same pinned bundle and the same redirected
# live state (swallow log, lane quota, loop claim) as every other test.
require_relative "test/test_helper"
