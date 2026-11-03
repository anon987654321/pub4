# frozen_string_literal: true

# Turbo::StreamsChannel serves any stream whose signed name it is given. A
# signed-out visitor connects as nobody (ApplicationCable::Connection), so the
# channel checks the stream is one of the public ones before it streams.
# after_initialize, not to_prepare: the channel is the gem's and is not
# reloaded, so the callback is added once.
Rails.application.config.after_initialize do
  Turbo::StreamsChannel.before_subscribe do
    next if current_user

    reject unless ApplicationCable::PublicStreams.public?(verified_stream_name_from_params)
  end

  # Somebody connected is still asked whether the stream is theirs: a removed
  # group member keeps a validly signed name for the conversation they left.
  Turbo::StreamsChannel.before_subscribe do
    next unless current_user

    reject unless ApplicationCable::PrivateStreams.allowed?(verified_stream_name_from_params, current_user)
  end
end
