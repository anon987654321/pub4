# frozen_string_literal: true

# The rack: named emulations of specific studio hardware.
#
# Each entry below is one real machine, and each is described by what it
# measurably does rather than by how it is supposed to feel. That distinction
# matters. "Warmth" is not a specification; second-harmonic distortion at a
# stated level is. Where a manufacturer or an engineer has said in print what
# a box does, the comment says so and the settings follow it.
#
# The units compose. A signal path of neve_80 into stc8 into gml_matte is three
# entries joined with commas, which is also how the equipment would have been
# patched together.
#
# What is honest about this and what is not: these reproduce the documented
# BEHAVIOUR of each machine -- its harmonic bias, its frequency response, its
# time constants. They do not reproduce its circuit. An emulation built this way
# gets you most of the way to the character and none of the way to the myth,
# which is the correct trade for a pure-Ruby engine with no plugin host.
module Outboard
  module_function

  # --------------------------------------------------------- Crane Song HEDD
  #
  # The Harmonically Enhanced Digital Device, designed by Dave Hill. Its whole
  # premise is that you choose your distortion rather than avoid it, and it
  # offers three kinds by name.
  #
  # Dave Cooley mastered Donuts, and Crane Song boxes are what he reached for.

  # A note on how these were built, because it decides whether they are worth
  # anything.
  #
  # Each was measured, not guessed. A one-kilohertz tone goes in, and the energy
  # at two and three kilohertz comes out -- the second and third harmonic -- as a
  # level below the tone itself. The figures quoted per unit are those readings.
  # The first attempt at these used aexciter, which produced nothing at all: its
  # `freq` is a SCOPE, so it ignores everything below five kilohertz, and a one
  # kilohertz tone passed through untouched. It measured -93 dB, the noise floor.
  # Had nobody measured, four units would have shipped doing nothing.
  #
  # Note also that asoftclip's `param` runs the opposite way to the intuition:
  # higher is more distortion, not less.

  # TRIODE. Per Crane Song: the even-order harmonics of a single-ended valve
  # stage. Even harmonics are octaves of the note being played, so the ear files
  # them as tone rather than as distortion -- this is what "warm" means when the
  # word is used carefully.
  #
  # Even harmonics require an ASYMMETRIC transfer curve: a shape that treats the
  # top half of the waveform differently from the bottom. A symmetric one, no
  # matter how hard it is driven, produces only odd harmonics. So the signal is
  # pushed off centre, clipped, and pulled back -- which is, near enough, what a
  # valve stage biased to one side does.
  #
  # Measured: 2nd harmonic -37.5 dB, 3rd -60.7 dB. Twenty-three decibels of
  # even-order bias, which is the triode signature.
  def hedd_triode(drive: 12, offset: 0.35, param: 2.4)
    "volume=#{drive}dB,dcshift=shift=#{offset}," \
      "asoftclip=type=tanh:param=#{param}:oversample=4," \
      "dcshift=shift=-#{offset},highpass=f=20,volume=-#{drive}dB"
  end

  # PENTODE. Per Crane Song: mostly third harmonic, and brighter -- they note it
  # sounds like a high-end boost without the drawbacks of one, because it works
  # across the spectrum rather than lifting a band.
  #
  # Odd harmonics are not octaves. The third above a note is a twelfth -- a fifth
  # in the next octave up -- which is why pentode reads as edge and presence
  # where triode reads as body. A symmetric clipper gives odd harmonics and
  # nothing else, so this is the simpler of the two.
  #
  # Measured: 3rd harmonic -35.3 dB, 2nd -91.8 dB. The bias is total.
  def hedd_pentode(drive: 24, param: 2.4)
    "volume=#{drive}dB,asoftclip=type=tanh:param=#{param}:oversample=4,volume=-#{drive}dB"
  end

  # TAPE. Per Crane Song: the compressed sound of driving an analogue recorder
  # into overload. Two things at once, and both are needed -- the soft clipping
  # of the tape itself, and the gentle levelling that comes with it.
  #
  # An arctangent curve rather than a hyperbolic tangent: it leaves the knee
  # earlier and rounds more gradually, which is closer to how tape approaches
  # saturation than to how a transistor does.
  #
  # Measured: 3rd harmonic -56.2 dB. Gentler than the pentode by design; the
  # compressor after it carries as much of the character as the clipping does.
  def hedd_tape(drive: 14, param: 2.2)
    "volume=#{drive}dB,asoftclip=type=atan:param=#{param}:oversample=4,volume=-#{drive}dB," \
      "acompressor=threshold=-16dB:ratio=2.5:attack=8:release=180:makeup=1.1"
  end

  # ------------------------------------------------------- Crane Song STC-8
  #
  # The compressor Cooley put Donuts through, and the specific thing he did with
  # it: he timed the release to each track's tempo. His words were that he did it
  # to preserve the disorienting compression pump -- to take the intensity
  # further rather than smooth it away.
  #
  # That is the opposite of the usual advice, which is to set a release that
  # makes compression inaudible. Here the compression is meant to be heard, and
  # tying it to the tempo makes it part of the rhythm instead of a fault in it.
  #
  # Release is one eighth note, so the bus has recovered exactly as the next
  # offbeat lands.
  def stc8(bpm:, threshold: -14, ratio: 2.0)
    release = bpm.to_f.positive? ? (60_000.0 / bpm / 2.0).round : 300
    "acompressor=threshold=#{threshold}dB:ratio=#{ratio}:attack=15:" \
      "release=#{release.clamp(50, 1000)}:makeup=1.08:detection=rms"
  end

  # ------------------------------------------------------------- GML 8200
  #
  # George Massenburg's parametric, and the other half of what Cooley described:
  # he used it for top end, and said he was not after a slick top at the time --
  # he called the result matte.
  #
  # A matte top is a WIDE, shallow shelf placed high. It lifts air across the
  # whole top octave without putting an edge on any one frequency. A narrow
  # boost is the slick sound he was avoiding, and the difference between the two
  # is entirely the width.
  def gml_matte(gain: 2.0, hz: 11_000)
    "equalizer=f=#{hz}:t=h:w=0.5:g=#{gain}"
  end

  # ------------------------------------------------- Neve 80-series console
  #
  # The 8028 and 8078, the desks the seventies are recorded on.
  #
  # Two documented properties. First, transformers: the signal leaves at close
  # to microphone level and is brought back up through output transformers,
  # which are not flat -- the core lifts the low bass slightly and the top rolls
  # away early. Second, the discrete class-A stages depart from linear as they
  # are pushed, and the sum of many small departures across a mix is what people
  # mean by the sound of the desk.
  #
  # Both are small. The temptation to make them large is what makes an emulation
  # sound like an emulation.
  #
  # The nonlinearity is asymmetric, like the triode and for the same reason:
  # transformer cores saturate asymmetrically, and a desk full of them reads as
  # warm rather than as harsh. Measured: 2nd harmonic -54.1 dB, 3rd -75.4 dB.
  # A sixth of the triode's distortion -- audible across a whole mix, inaudible
  # on any one sound, which is what a console does.
  def neve_80(drive: 8, offset: 0.18, param: 1.6, lf_db: 1.2)
    "equalizer=f=55:t=q:w=0.8:g=#{lf_db}," \
      "volume=#{drive}dB,dcshift=shift=#{offset}," \
      "asoftclip=type=tanh:param=#{param}:oversample=4," \
      "dcshift=shift=-#{offset},highpass=f=20,volume=-#{drive}dB," \
      "lowpass=f=18500"
  end

  # ------------------------------------------------------------- API console
  #
  # The other transformer desk, and the counterweight to the Neve: where the
  # Neve is round, the API is forward. Its reputation rests on speed -- fast
  # amplifiers, a lift through the presence region where a snare's crack lives.
  #
  # Faster and brighter than neve_80, deliberately. Reach for this one on a
  # drum-led track and the Neve on a sample-led one.
  #
  # Symmetric where the Neve is asymmetric: more third harmonic, less second,
  # which is the edge people describe when they call an API aggressive and a
  # Neve round. Comparable amount of distortion, different flavour of it.
  #
  # Measured: 3rd harmonic -58.8 dB, 2nd below the floor. Set against the Neve's
  # -54 dB of SECOND, the two desks distort about equally and sound nothing
  # alike, which is the whole point of having both.
  #
  # The cubic curve was tried first, as the more obviously "different" shape,
  # and abandoned: it barely saturates at any setting this side of unusable.
  # It reached only -61 dB at twenty-two decibels of drive.
  def api_console(drive: 12, param: 2.4)
    "equalizer=f=75:t=q:w=1.0:g=1.0," \
      "equalizer=f=3200:t=q:w=1.4:g=1.4," \
      "volume=#{drive}dB,asoftclip=type=tanh:param=#{param}:oversample=4,volume=-#{drive}dB," \
      "lowpass=f=19500"
  end

  # ------------------------------------------------------- Tape machine
  #
  # A reel-to-reel, modelled the way CHOW Tape models one: as a machine with
  # parts, not as an effect. Four things happen to audio on tape and all four
  # are here.
  #
  #   HEAD BUMP.  A low resonance around fifty hertz, from the geometry of the
  #               playback head. It is why tape sounds big at the bottom.
  #   HF LOSS.    The top falls away, earlier at slower tape speeds.
  #   WOW.        Slow pitch drift, under a hertz, from an eccentric reel.
  #   FLUTTER.    Fast pitch drift, a few hertz, from the capstan.
  #
  # Wow and flutter are pitch modulation, which is what the vibrato filter does.
  #
  # Its depth turns out to map one-to-one onto percent of pitch deviation --
  # measured by tracking a five-kilohertz tone, where a depth of 0.08 gave
  # exactly plus or minus 0.08 percent. The first version of this unit asked for
  # 0.0022, which is twenty-eight times below what a machine actually does and
  # measured as a dead flat line: no wow at all. A published specification for a
  # studio deck is under 0.05 percent combined; a tired one, or a turntable,
  # reaches 0.1 to 0.3. These sit just above the good machine, which is where a
  # record that has been played a few hundred times sits.
  def tape_machine(speed: :ips15, wow: 0.08, flutter: 0.03)
    hf = speed == :ips7 ? 12_500 : 16_500
    bump = speed == :ips7 ? 2.2 : 1.5
    "equalizer=f=50:t=q:w=1.2:g=#{bump}," \
      "vibrato=f=0.7:d=#{wow}," \
      "vibrato=f=6.3:d=#{flutter}," \
      "lowpass=f=#{hf}"
  end

  # ---------------------------------------------------------- Pultec EQP-1A
  #
  # A passive tube equaliser from the 1950s, and the one piece of outboard whose
  # most famous use is a thing its own manual warns against.
  #
  # Its low band has separate boost and attenuate knobs at the same selected
  # frequency, and turning up both should cancel. It does not, because the two
  # circuits are not mirror images: the BOOST is a broad, gentle shelf that
  # starts below the frequency, while the CUT is narrower and starts slightly
  # above it. Use both at 100 Hz and what you get is a lift underneath and a dip
  # at 200 to 400 -- weight added exactly where a kick lives, and mud removed
  # exactly where mud lives.
  #
  # No single control does this, which is why engineers still reach for it
  # seventy years on. It is also precisely the shape a hip-hop low end wants.
  def pultec_low(hz: 100, boost: 4.0, cut: 3.0)
    "equalizer=f=#{hz}:t=q:w=0.7:g=#{boost}," \
      "equalizer=f=#{(hz * 2.8).round}:t=q:w=1.1:g=-#{cut}"
  end

  # The matching high band: a broad lift with a small dip below it, which is how
  # the Pultec adds air without the boost sounding like a boost.
  def pultec_air(hz: 12_000, boost: 2.5)
    "equalizer=f=#{hz}:t=h:w=0.6:g=#{boost}," \
      "equalizer=f=#{(hz * 0.35).round}:t=q:w=1.4:g=-1.0"
  end

  # ------------------------------------------------------------- compressors
  #
  # Three ways of turning a signal down, which sound nothing alike because of
  # what does the turning.

  # TELETRONIX LA-2A. An optical compressor: the signal drives a small lamp, and
  # a light-sensitive resistor beside it does the gain reduction. The lamp and
  # the cell both take time to respond and neither is linear, so the release is
  # in two stages -- a fast part and a long slow tail -- and it depends on how
  # hard and how long the unit has been working.
  #
  # This is why an LA-2A is described as transparent while compressing heavily:
  # it never grabs, and it lets go slowly enough that you hear the level change
  # as an arrangement decision rather than as an effect. No attack control,
  # because the lamp decides.
  def la2a(threshold: -18, ratio: 3.0)
    "acompressor=threshold=#{threshold}dB:ratio=#{ratio}:attack=10:release=600:" \
      "knee=8:detection=rms:makeup=1.15"
  end

  # UREI 1176. A field-effect transistor does the gain reduction, and it does it
  # in microseconds -- the fastest attack here by two orders of magnitude. Fast
  # enough to catch the very front of a snare, which is why it grabs a drum bus
  # and makes it sound like a record.
  #
  # The famous setting is all four ratio buttons pushed in at once, which the
  # unit was never designed to allow: it produces a very high ratio with a
  # distorted, lagging knee. That is what the aggressive figures below are.
  def fet1176(threshold: -16, ratio: 12.0)
    "acompressor=threshold=#{threshold}dB:ratio=#{ratio}:attack=0.4:release=90:" \
      "knee=2:detection=peak:makeup=1.25"
  end

  # FAIRCHILD 670. A variable-mu limiter -- the gain reduction happens inside
  # the valves themselves, whose amplification falls as the signal drives them.
  # Twenty valves, a hundred and fifty pounds, and on most of the Beatles
  # catalogue.
  #
  # Variable-mu units are slow and gentle and the ratio rises with how hard they
  # are hit, so they flatter a mix rather than control it. Used here as glue,
  # never as a limiter.
  # knee maxes at 8 in this build, not 12. A rejected value fails the WHOLE
  # chain, so the glue rack rendered nothing at all until this was clamped.
  def fairchild670(threshold: -20, ratio: 1.8)
    "acompressor=threshold=#{threshold}dB:ratio=#{ratio}:attack=25:release=400:" \
      "knee=8:detection=rms:makeup=1.1"
  end

  # ------------------------------------------------- Roland RE-201 Space Echo
  #
  # A tape loop running past three playback heads, with a spring reverb bolted
  # on. Two photographs of one sit in Flying Lotus's studio, and it is on a great
  # deal of what he has made.
  #
  # What makes it sound like itself is not the delay times -- any box can do
  # taps. It is that the tape is a physical loop being re-recorded on every pass,
  # so each repeat is a generation further from the original:
  #
  #   DARKER. The tape loses top end every time round. By the fourth repeat
  #   there is very little above a few kilohertz, which is why a Space Echo tail
  #   fades into the track instead of cluttering it. A digital delay repeating a
  #   bright sound stays bright and quickly becomes a mess.
  #
  #   UNSTEADY. The transport wows, and the wow accumulates -- the fifth repeat
  #   has been through it five times. The tail drifts in pitch, which is the
  #   sound people mean by "tape delay" and the reason a clean one sounds wrong.
  #
  #   THREE HEADS. Fixed positions on the loop, not free times, so the taps are
  #   in a fixed ratio to each other. Modelled here at roughly 1 : 1.9 : 2.8,
  #   which is where the real heads sit.
  #
  # The darkening is done by putting the lowpass BETWEEN two echo stages rather
  # than after them, so the second stage's repeats are filtered copies of the
  # first stage's -- which is what a feedback loop through tape actually does,
  # and what a single filtered send does not.
  def space_echo(time_ms: 240, feedback: 0.55, mix: 0.4, wow: 0.12)
    short = time_ms.round
    medium = (time_ms * 1.9).round
    long = (time_ms * 2.8).round
    "asplit=2[se_dry][se_wet];" \
      "[se_wet]aecho=0.9:#{feedback}:#{short}|#{medium}|#{long}:0.6|0.45|0.3," \
      "lowpass=f=3200,vibrato=f=0.9:d=#{wow}," \
      "aecho=0.85:#{(feedback * 0.8).round(2)}:#{(time_ms * 3.6).round}|#{(time_ms * 5.1).round}:0.4|0.25," \
      "lowpass=f=2200,highpass=f=180,volume=#{mix}[se_verb];" \
      "[se_dry][se_verb]amix=inputs=2:weights=1 1:normalize=0"
  end

  # ------------------------------------------------------------- mono bass
  #
  # Everything below the crossover collapsed to the centre.
  #
  # This is a cutting-lathe rule that outlived the lathe. Bass energy that
  # differs between the two channels moves the cutting stylus vertically, and
  # enough of it lifts the needle out of the groove -- so records were always cut
  # with a mono bottom. It survives because it turns out to be right for other
  # reasons: a club system's subwoofer is one speaker fed from both channels, so
  # stereo bass partly cancels before anyone hears it, and low frequencies carry
  # no directional information to a listener anyway. The ear locates sound below
  # about 150 Hz by which side is louder, not by anything in the waveform.
  #
  # What it buys is loudness. Two channels of bass in phase are 6 dB louder than
  # two fighting, so the limiter downstream has less to do and the track hits
  # harder at the same measured level.
  def mono_bass(hz: 120)
    "asplit=2[mb_lo][mb_hi];" \
      "[mb_lo]lowpass=f=#{hz},pan=stereo|c0=0.5*c0+0.5*c1|c1=0.5*c0+0.5*c1[mb_mono];" \
      "[mb_hi]highpass=f=#{hz}[mb_wide];" \
      "[mb_mono][mb_wide]amix=inputs=2:weights=1 1:normalize=0"
  end

  # ------------------------------------------------- Console summing bus
  #
  # The stage every other unit here skips. A desk does not only colour each
  # channel on the way in -- the channels then MEET, on a summing bus with its
  # own transformer, its own coupling capacitors, and its own phase behaviour.
  # That bus is why a mix printed through a console does not sound like the same
  # mix summed in software, and it is the last analog thing to touch the audio.
  #
  # Three parts, and only one of them is distortion.
  #
  #   PHASE ROTATION. Two allpass sections, at 90 Hz and 1.8 kHz. An allpass
  #                   changes phase and NOTHING else, which is exactly what a
  #                   chain of transformers and coupling caps does to a signal.
  #                   Measured: 0.00 dB change at 60, 200, 1k, 4k and 12k Hz,
  #                   while phase moves 226, 61, 261, 100 and 28 degrees at those
  #                   same frequencies. That is the "phasy" character, and it is
  #                   real phase rather than an effect pretending to be one.
  #
  #   MOVEMENT.       A very slow phaser, 0.1 Hz -- one sweep every ten seconds.
  #                   Not an audible whoosh; a bus that will not sit perfectly
  #                   still, which is the difference between analog and a plugin
  #                   bypassed.
  #
  #   TRANSFORMER.    Gentle asymmetric saturation. Measured 2nd -61.3 dB, 3rd
  #                   -73.8 dB on the same rig that reads neve_80 at 2nd -48.1
  #                   and api_console at 3rd -46.6 -- so roughly 13 dB gentler
  #                   than a channel strip, which is right. A summing bus is not
  #                   a drive stage; if you can hear it working it is wrong.
  #
  # Note the rig: those three figures are comparable to each other because they
  # were taken together. They read 6-12 dB hotter than the older per-unit figures
  # quoted above, which were measured with a different setup -- compare within a
  # set, not across them.
  #
  # TWO NUMBERS ARE NOT FREE CHOICES, and both were found by measurement:
  #
  #   aphaser speed has a hard floor of 0.1 in ffmpeg. Below it the filter is
  #   REFUSED, and a refused filter does not degrade -- it takes the entire chain
  #   with it and the render dies. 0.1 is the slowest legal sweep, which is also
  #   the one wanted here.
  #
  #   aphaser attenuates hard and silently: in_gain 0.5 with the default out_gain
  #   0.72 measured -8.56 dB mean across the band. out_gain 1.9 brings it to
  #   -0.13 dB. With the saturator's own loss on top, the closing makeup is -1.0
  #   dB rather than the -5.0 dB that symmetry with the drive would suggest;
  #   measured net for the whole unit is -0.08 dB. An uncompensated version of
  #   this cost 4 dB and would have read as "the phasy racks are quieter".
  def console_sum(drive: 5, offset: 0.10, param: 1.2, makeup: -1.0, speed: 0.1)
    "allpass=f=90:width_type=q:w=0.6:order=2," \
      "allpass=f=1800:width_type=q:w=0.5:order=2," \
      "aphaser=in_gain=0.5:out_gain=1.9:delay=3.2:decay=0.15:speed=#{speed}:type=t," \
      "volume=#{drive}dB,dcshift=shift=#{offset}," \
      "asoftclip=type=tanh:param=#{param}:oversample=4," \
      "dcshift=shift=-#{offset},highpass=f=18,volume=#{makeup}dB"
  end

  # ------------------------------------------------------------------ racks
  #
  # Signal paths, in patch order. A rack is a list of unit names; `chain` turns
  # one into the filter string.
  RACKS = {
    # What Donuts went through, as closely as this can be said: a console, then
    # the Crane Song compressor timed to the track, then the GML for the top.
    #
    # The triode is NOT in this rack, and the reason is worth keeping.
    #
    # On one instrument, second-harmonic distortion at -37 dB is warmth -- the
    # octave above every note, which the ear files as tone. On a finished mix it
    # is overdrive, because a mix is not one note: every pair of frequencies in
    # it intermodulates through the same nonlinearity and produces sums and
    # differences that belong to no note at all. Measured, this rack with the
    # triode in it put 1.3 percent distortion on the master, on top of the
    # SP-1200 and vinyl emulation already in the path, and the samples came back
    # sounding like guitars through an overdriven amp. Without it: 0.2 percent,
    # which is where a mastering chain belongs.
    #
    # The unit is still here and still measured. It belongs on a single voice.
    donuts: %i[neve_80 stc8 gml_matte mono_bass],
    # Warmer and slower. The tape machine ahead of everything, so the console
    # colours what the tape already did.
    # Same reasoning: hedd_tape is a saturator too, and two on a master is one
    # too many. The tape machine ahead of the console carries the character.
    tape_first: %i[tape_machine neve_80 stc8 console_sum gml_matte mono_bass],
    # Forward and bright, for tracks the drums lead.
    forward: %i[api_console stc8 gml_matte mono_bass],
    # The console alone, for when the material arrives already finished.
    light: %i[neve_80 stc8],

    # Three racks that exist so the compressors are reachable. They were built
    # and measured and then put in no rack and given no other caller, which is
    # this codebase's most repeated defect and was worth fixing on its own terms.
    #
    # GLUE. A variable-mu limiter flatters a mix rather than controlling it --
    # slow, gentle, and its ratio rises with how hard it is hit. The Fairchild
    # before the console rather than after, so the desk colours something already
    # sitting together.
    glue: %i[fairchild670 neve_80 console_sum gml_matte mono_bass],

    # SMOOTH. The LA-2A has no attack control because a light bulb decides its
    # timing, and the result is heavy compression you do not hear working. For
    # material with a wide dynamic range, where the STC-8's tempo pump would be
    # the wrong kind of audible.
    smooth: %i[neve_80 la2a pultec_air console_sum gml_matte mono_bass],

    # SNAP. The 1176 catches the front of a transient in microseconds, which is
    # what makes a drum bus sound like a record. Paired with the API, since both
    # are the fast, forward end of the collection.
    snap: %i[api_console fet1176 hedd_pentode gml_matte mono_bass],
  }.freeze

  DEFAULT_RACK = :donuts

  # Builds one rack into a filter chain.
  #
  # Unknown names are dropped rather than raised on, and the drop is reported by
  # the caller: a misspelt unit that silently disappears is exactly the kind of
  # dead configuration this codebase keeps finding.
  def chain(rack = DEFAULT_RACK, bpm:, missing: nil)
    units = RACKS.fetch(rack.to_sym) { RACKS.fetch(DEFAULT_RACK) }
    units.filter_map do |unit|
      case unit
      when :hedd_triode then hedd_triode
      when :hedd_pentode then hedd_pentode
      when :hedd_tape then hedd_tape
      when :stc8 then stc8(bpm:)
      when :gml_matte then gml_matte
      when :neve_80 then neve_80
      when :api_console then api_console
      when :tape_machine then tape_machine
      when :mono_bass then mono_bass
      when :la2a then la2a
      when :fet1176 then fet1176
      when :fairchild670 then fairchild670
      when :pultec_air then pultec_air
      when :pultec_low then pultec_low
      when :console_sum then console_sum
      when :space_echo then space_echo
      else
        missing&.call(unit)
        nil
      end
    end.join(",")
  end

end
