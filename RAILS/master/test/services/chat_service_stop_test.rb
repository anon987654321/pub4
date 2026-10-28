# frozen_string_literal: true

require "test_helper"

# The stop path: a stream write that fails because the client's side of the
# SSE connection is gone cancels the turn's CancellationToken and unwinds the
# provider call through the on_chunk raise, so a stopped or departed client
# burns no further tokens. The stub seam is TurnRouter.call, the one
# collaborator ChatService hands the turn to.
class ChatServiceStopTest < ActiveSupport::TestCase
  # Writes succeed while the client holds the socket, then raise IOError the
  # way Falcon surfaces a closed response body.
  class DyingStream
    attr_reader :writes

    def initialize(fail_after:)
      @writes = []
      @fail_after = fail_after
      @closed = false
    end

    def closed? = @closed

    def write(data)
      raise IOError, "client disconnected" if @writes.length >= @fail_after

      @writes << data.to_s
    end

    def close
      @closed = true
    end
  end

  setup do
    Fiber[:master_conversation] = nil
    @dir = Dir.mktmpdir
    @bus = Master::Trace::EventBus.new(event_log: Master::Trace::Log::Event.new(root: @dir))
    @mine = "cccccccccccccccccccccccccccccccc"
  end

  teardown do
    Fiber[:master_conversation] = nil
    FileUtils.rm_rf(@dir)
  end

  def build_service(stream)
    ChatService.new(
      container: { bus: @bus },
      params: { message: "tell me about bergen" },
      stream:,
      logger: Rails.logger,
      tier: "visitor",
      unlocked: false,
      author: false,
      conversation: @mine,
    )
  end

  def with_stubbed_turn_router(stub)
    router = Master::CLI::TurnRouter.singleton_class
    router.send(:alias_method, :call_before_stop_stub, :call)
    router.send(:define_method, :call, stub)
    yield
  ensure
    router.send(:remove_method, :call)
    router.send(:alias_method, :call, :call_before_stop_stub)
    router.send(:remove_method, :call_before_stop_stub)
  end

  test "a failed write on a closed socket cancels the turn token and unwinds on_chunk" do
    stream = DyingStream.new(fail_after: 3)
    seen = {}
    raised = false
    stub = lambda do |**kwargs|
      seen[:cancellation] = kwargs[:cancellation]
      kwargs[:on_chunk].call("a chunk for nobody")
      seen[:turn_returned] = true
    rescue ChatService::ClientGone
      raised = true
      raise
    end

    with_stubbed_turn_router(stub) do
      build_service(stream).call
    end

    assert raised, "the disconnect did not unwind through on_chunk"
    assert_instance_of Master::Core::CancellationToken, seen[:cancellation]
    assert seen[:cancellation].cancelled?
    assert_equal "client disconnected", seen[:cancellation].reason
    refute seen[:turn_returned], "the turn ran on after the client was gone"
  end

  test "a disconnected client receives no further frames and the stream closes" do
    stream = DyingStream.new(fail_after: 3)
    stub = lambda do |**kwargs|
      kwargs[:on_chunk].call("a chunk for nobody")
      Master::Result.ok({ rendered: "unreachable" })
    end

    with_stubbed_turn_router(stub) do
      build_service(stream).call
    end

    assert stream.closed?
    joined = stream.writes.join
    assert_equal 3, stream.writes.length
    refute joined.include?("a chunk for nobody")
    refute joined.include?("[DONE]"), "a stopped turn still wrote its terminal frame"
    refute joined.include?("ERROR: "), "a stopped turn rendered the public error to nobody"
  end

  test "a cancelled turn writes its terminal frame and no error frame" do
    stream = DyingStream.new(fail_after: 1_000)
    stub = lambda do |**kwargs|
      kwargs[:cancellation].cancel!(reason: "client disconnected")
      Master::Result.err("fold0: cancelled: client disconnected", category: :cancelled)
    end

    with_stubbed_turn_router(stub) do
      build_service(stream).call
    end

    assert stream.closed?
    joined = stream.writes.join
    assert joined.include?("[DONE]")
    refute joined.include?("ERROR: ")
    refute joined.include?("cancelled: client disconnected")
  end
end
