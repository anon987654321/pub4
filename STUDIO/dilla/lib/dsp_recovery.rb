def recover_slowed_transients!(path, destination:)
  # Transient recovery and spectral excitation for slowed audio.
  # 1. High-pass the source to isolate the 'snap' range (2kHz - 8kHz).
  # 2. Apply a fast-attack compressor/limiter to flatten peaks.
  # 3. Use a subtle high-shelf or spectral tilt to add brilliance.
  # 4. Blend the recovered transients back into the original slowed signal.
  
  src = path
  recovered = "#{path}.transients.wav"
  
  # Recovery chain: highpass -> compressor (fast) -> highshelf (excitation)
  # highpass=f=2000: remove mud
  # compressor: attack=1ms, release=50ms, ratio=4: squash the transients into a consistent 'click'
  # highshelf: f=5000, g=6dB: excitation
  recovery_chain = "highpass=f=2000,acompressor=attack=1:release=50:ratio=4:threshold=-20dB,highshelf=f=5000:g=6"
  
  # Mix chain: [0:a] is original, [1:a] is recovered transients.
  # We use amix to blend them. Recovered transients are kept subtle (gain 0.3).
  mix_chain = "[0:a][1:a]amix=inputs=2:weights=1.0 0.3:normalize=0"
  
  begin
    # Step 1: Extract and process transients
    sh! "ffmpeg", "-y", "-i", src, "-af", recovery_chain, "-c:a", "pcm_s16le", recovered
    
    # Step 2: Mix recovered transients back into original
    sh! "ffmpeg", "-y", "-i", src, "-i", recovered, "-filter_complex", mix_chain, 
        "-c:a", "pcm_s16le", destination
        
    File.unlink(recovered) if File.file?(recovered)
    destination
  rescue StandardError => e
    warn "transient recovery failed: #{e.message}"
    src
  end
end
