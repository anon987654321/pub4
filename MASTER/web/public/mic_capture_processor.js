// AudioWorklet that keeps the last N seconds of microphone audio.
//
// Smart Turn needs the waveform, and SpeechRecognition does not give one out —
// it returns text. So the mic is opened a second time, in parallel, purely to
// keep a rolling buffer for the endpoint model.
//
// The ring lives on this side of the worklet boundary rather than posting every
// 128-sample block to the main thread: at 16kHz that would be 125 messages a
// second doing nothing but copying. The main thread asks for a snapshot when it
// is actually about to decide something.
class MicCaptureProcessor extends AudioWorkletProcessor {
  constructor(options) {
    super();
    const seconds = options?.processorOptions?.seconds || 8;
    // sampleRate is a global inside an AudioWorkletGlobalScope.
    this.capacity = Math.ceil(seconds * sampleRate);
    this.buffer = new Float32Array(this.capacity);
    this.write = 0;
    this.filled = 0;
    this.port.onmessage = (event) => {
      if (event.data?.type === "snapshot") this.postSnapshot();
      if (event.data?.type === "reset") { this.write = 0; this.filled = 0; }
    };
  }

  postSnapshot() {
    const out = new Float32Array(this.filled);
    if (this.filled < this.capacity) {
      out.set(this.buffer.subarray(0, this.filled));
    } else {
      // Oldest sample is at the write head once the ring has wrapped.
      const tail = this.capacity - this.write;
      out.set(this.buffer.subarray(this.write), 0);
      out.set(this.buffer.subarray(0, this.write), tail);
    }
    this.port.postMessage({ type: "snapshot", samples: out, sampleRate }, [out.buffer]);
  }

  process(inputs) {
    const channel = inputs[0]?.[0];
    if (!channel) return true;
    for (let i = 0; i < channel.length; i += 1) {
      this.buffer[this.write] = channel[i];
      this.write = (this.write + 1) % this.capacity;
    }
    this.filled = Math.min(this.filled + channel.length, this.capacity);
    return true;
  }
}

registerProcessor("mic-capture", MicCaptureProcessor);
