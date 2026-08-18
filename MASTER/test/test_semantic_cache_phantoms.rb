# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "unwrap_error"
require "io/semantic_cache"

# The cache runs before the phantom guard judges the response, so storing a
# degenerate one makes it the permanent answer to that prompt: every identical
# question replays it, trips the same detector, and PhantomRecovery's ladder —
# which counts consecutive phantoms — reaches halt with no clean response in
# between to reset it.
#
# Measured on vm23 before this: the same question answered correctly on a cache
# miss, then halted on the second and third ask.
class TestSemanticCachePhantoms < Minitest::Test
  # 60 characters, four times over — comfortably past "same 60-char span repeats
  # >= 3 times" in data/rules.yml.
  SPAN = ("the quick brown fox jumps over the lazy dog and keeps going ")
  LOOPING = SPAN * 4
  CLEAN = "Done. The queue drained 22 jobs and none failed."

  def with_cache
    Dir.mktmpdir do |root|
      yield Master::Io::SemanticCache.new(root: root, ttl: 600)
    end
  end

  # Guard the guard: if this text stopped being detectable the test below would
  # pass while measuring nothing.
  def test_the_fixture_is_actually_a_phantom
    refute_nil Master::PhantomRecovery.detect(LOOPING), "the looping fixture is not detected as a phantom"
    assert_nil Master::PhantomRecovery.detect(CLEAN), "the clean fixture is detected as a phantom"
  end

  def test_a_clean_response_is_cached
    with_cache do |cache|
      calls = 0
      2.times { cache.fetch("what drained", "m1") { calls += 1; CLEAN } }

      assert_equal 1, calls, "a clean response was not served from cache on the second ask"
    end
  end

  def test_a_degenerate_response_is_not_cached
    with_cache do |cache|
      calls = 0
      2.times { cache.fetch("what heter du", "m1") { calls += 1; LOOPING } }

      assert_equal 2, calls,
                   "a phantom response was cached, so the next identical question replays it and the " \
                   "consecutive-phantom ladder climbs to a halt"
    end
  end

  # The refusal must be about the content, not about the prompt: the same prompt
  # must cache normally once the model stops looping.
  def test_the_same_prompt_caches_once_the_response_is_clean
    with_cache do |cache|
      cache.fetch("hva heter du", "m1") { LOOPING }

      calls = 0
      2.times { cache.fetch("hva heter du", "m1") { calls += 1; CLEAN } }

      assert_equal 1, calls, "a prompt that once produced a phantom can never be cached again"
    end
  end

  # An unfamiliar result shape loses caching rather than being skipped silently.
  def test_an_unreadable_result_shape_is_still_cached
    with_cache do |cache|
      calls = 0
      2.times { cache.fetch("odd", "m1") { calls += 1; { some: "structure" } } }

      assert_equal 1, calls, "a result this cannot read as text stopped being cached"
    end
  end
end
