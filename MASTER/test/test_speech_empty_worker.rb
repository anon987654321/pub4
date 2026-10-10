# frozen_string_literal: true

require_relative "test_helper"
require "socket"
require "stringio"
require "tmpdir"

# A pool worker that answers its health ping but synthesises nothing used to win every
# other round-robin turn. Its stream ended with a clean zero-length frame, which counted
# as an utterance spoken in silence; its whole-file turn fell to the older voices.
class TestSpeechEmptyWorker < Minitest::Test
  Speech = Master::Voice::Speech
  Sup = Master::Voice::TtsSupervisor

  # A worker that reads a request and answers with only the wire's end frame.
  def with_empty_worker
    Dir.mktmpdir("tts") do |dir|
      path = File.join("/tmp", "tts-#{Process.pid}-0.sock")
      File.unlink(path) if File.exist?(path)
      server = UNIXServer.new(path)
      thread = Thread.new do
        while (client = server.accept)
          client.gets
          client.write([0].pack("Q>"))
          client.close
        end
      rescue IOError, Errno::EBADF
        nil
      end
      yield path
    ensure
      server&.close
      thread&.join(1)
      File.unlink(path) if path && File.exist?(path)
    end
  end

  def test_a_stream_with_no_audio_is_a_failure_and_retires_the_worker
    retired = []
    with_empty_worker do |path|
      Sup.stub(:next_socket, path) do
        Sup.stub(:retire_socket, ->(p, **) { retired << p }) do
          result = Speech.stream_edge_to_io(text: "Good, thanks.", voice_name: "en-US-JennyNeural",
                                            style_config: { rate: "+0%", pitch: "+0Hz" }, io: StringIO.new)

          refute result.ok, "zero bytes must not read as a spoken utterance"
          assert_equal 0, result.bytes
          assert_equal [path], retired
        end
      end
    end
  end

  def test_retire_socket_reads_the_slot_from_the_path
    seen = []
    Sup.stub(:retire_daemon, ->(index) { seen << index }) do
      Sup.stub(:with_daemon_lock, ->(_root, index: 0, &blk) { blk.call }) do
        Sup.retire_socket("/nonexistent/.master/tts-1.sock")
      end
    end

    assert_equal [1], seen
  end
end
