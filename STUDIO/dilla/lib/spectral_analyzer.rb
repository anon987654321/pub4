# frozen_string_literal: true

# SpectralAnalyzer
# The 'Measure' part of the Render-Measure-Refine loop for audio.
# Analyzes the frequency spectrum of a render and computes deltas against a target signature.
class SpectralAnalyzer
  # We divide the spectrum into critical bands for analysis.
  BANDS = {
    sub: 20..60,
    mud: 60..250,
    low_mid: 250..500,
    mid: 500..2000,
    presence: 2000..5000,
    brilliance: 5000..20000
  }.freeze

  # analyze(path) uses ffprobe's show_spectrum to get magnitude data.
  # Since parsing raw spectrum output is heavy, we use a simplified
  # approach: extract the average RMS energy per band.
  def analyze(path)
    # Use ffprobe to get frequency data. We sample the spectrum at 1000 points.
    # output: a list of amplitudes for the bins.
    cmd = %Q(ffprobe -v error -f lavfi -i "amovie=#{path},asrc=sample_rate=44100,ebur128" -show_entries frame=loudness -of csv=p=0)
    # Note: ebur128 gives integrated loudness. For true spectral analysis,
    # we'd typically use a specialized Ruby gem or a python script.
    # For this loop, we'll approximate 'spectral tilt' via the ratio of
    # high-frequency energy to low-frequency energy using ffmpeg's
    # frequency analysis filter.
    
    # Simplified Spectral Measure: High-frequency energy vs Low-frequency energy
    # We run two passes: one for 'Mud' (60-250Hz) and one for 'Air' (5kHz+).
    mud_energy = measure_band(path, 60, 250)
    air_energy = measure_band(path, 5000, 20000)
    
    { mud: mud_energy, air: air_energy, tilt: air_energy / [mud_energy, 0.001].max }
  end

  def compute_delta(current, target)
    {
      mud_delta: target[:mud] - current[:mud],
      air_delta: target[:air] - current[:air],
      tilt_delta: target[:tilt] - current[:tilt]
    }
  end

  private

  def measure_band(path, low, high)
    # Use ffmpeg's firefilter to isolate band and compute RMS loudness
    filter = "highpass=f=#{low},lowpass=f=#{high},astats=measure=rms"
    cmd = %Q(ffmpeg -i "#{path}" -af "#{filter}" -f null - 2>&1)
    output = `#{cmd}`
    
    # Extract RMS value from astats output
    if output =~ /RMS level: ([-]?\d+\.\d+) dB/
      10**($1.to_f / 20.0) # Convert dB to linear amplitude
    else
      0.0
    end
  end
end
