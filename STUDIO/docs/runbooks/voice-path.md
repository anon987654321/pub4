# Runbook: voice path

Run on the target machine/device with actual STT/TTS and audio output. Mocked
workers can verify contracts, but cannot establish audible behavior or latency.

The repository’s declared voice policy expects English Christopher, Norwegian
Pernille/Finn, and Malay Yasmin/Osman according to the selected voice family.
Verify both the configured profile and the name actually rendered by the
runtime.

Record one artifact per important path:

- English, Norwegian and Malay output follows the configured policy; a voice
  does not drift unexpectedly between turns.
- Only one voice plays at a time. Queueing remains bounded; cancelled audio
  leaves no orphaned playback.
- Measure input acknowledgement, time to first audio, time to complete
  utterance, and turn-to-turn gaps with a monotonic clock.
- Interrupt by pressing the stop control and by speaking during playback where
  supported. Confirm playback stops and the next turn can start.
- Deny microphone permission, disconnect the STT service and force an STT/TTS
  timeout. Each failure receives a useful message and a declared fallback.
- Verify reduced-motion and quiet/low-volume paths where they apply.

Capture the target’s OS/browser/runtime, voice policy, model/provider, start and
end times, relevant logs and short audio samples appropriate for sharing.
Inspect logs for personal information before committing them. A passing voice
unit test alone does not close the real-device item.
