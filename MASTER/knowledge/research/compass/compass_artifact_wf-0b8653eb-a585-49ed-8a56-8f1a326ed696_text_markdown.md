# Production DNA of J Dilla, Flying Lotus, and Madlib

Three producers fundamentally reshaped beat-making through unconventional timing, lo-fi aesthetics, and jazz-influenced harmony. This technical breakdown documents their equipment, techniques, and chord progressions for implementation in music production code.

## J Dilla: The architect of humanized machine music

J Dilla's revolutionary contribution centers on **micro-timing manipulation**—offsetting individual drum hits by milliseconds to create the "drunk" or "loose" feel that defined a generation of hip-hop and neo-soul production. His primary instrument, the **Akai MPC3000 Limited Edition (#0449)**, now resides in the Smithsonian, operated at **96 PPQN** (pulses per quarter note), giving him 96 possible positions for each sound within a beat.

### Complete equipment list

**Samplers (progression):** E-mu SP-12 → E-mu SP-1200 (12-bit, used on Pharcyde's "Drop" and "Runnin'") → Akai MPC-60 → MPC-60 II → **Akai MPC3000** (primary) → Boss SP-303 (used on Donuts during hospital stays)

**Synthesizers:** Moog Minimoog Voyager (custom unit signed by Bob Moog, 2002), Korg MicroKORG, E-mu PK-6, Korg Electribe ESX-1, Yamaha Motif-Rack ES, Roland XV sound module

**Mixing/Recording:** Soundtracs Topaz console, Pro Tools TDM/HD Accel system, Digidesign ProControl, DBX 160X compressor, Yamaha SPX900 multi-effects (favored the "Symphonic" program with D-filter)

**Monitoring:** Technics SL-1200 MK2 turntables, Numark PT-01 portable turntable (late period)

### The "Dilla swing" timing mathematics

The MPC's swing function operates on a **50-75% range** where 50% equals straight time and 66% equals perfect triplet swing. Dilla reportedly used **subtle swing settings around 53-56%** on eighth notes, but his signature technique involved **turning quantization off entirely** and finger-drumming beats live for the full track duration.

**Critical timing formula for code implementation:**
- Hi-hats: Place odd/even hits on separate tracks; nudge the second track **forward** (ahead of beat)
- Snares: Nudge **slightly early** (back) to push the beat forward
- Kicks: Nudge **slightly late** (forward) to create laid-back contrast
- Typical tempo range: **82-92 BPM**

The MPC3000's nudge function shifts notes by increments of **1/96th of a quarter note**. Modern analysis suggests Dilla employed **quintuplet and septuplet swing**—odd tuplet groupings that don't fit standard subdivisions. A golden ratio swing approximation of **62.5%** (shifting the second note back by one 32nd note) captures some of his feel.

### Chord progressions for code implementation

**Fantastic Vol. 2 (2000)**

```javascript
const fantasticVol2 = {
  "fall_in_love": {
    key: "F minor",
    bpm: 91,
    progression: ["Bbm", "Ab", "Fm7", "Fm"],
    roman: ["iv", "bIII", "i7", "i"],
    qualities: ["minor", "major", "minor7", "minor"]
  },
  "climax": {
    key: "E major",
    bpm: 96,
    progression: ["Emaj7", "G#m7", "G#m7", "G#maj7"],
    roman: ["Imaj7", "iii7", "iii7", "IIImaj7"],
    qualities: ["major7", "minor7", "minor7", "major7"]
  },
  "get_dis_money": {
    key: "C# minor",
    bpm: 90,
    progression: ["C#m", "G#m", "A#7", "C#"],
    roman: ["i", "v", "VI7", "I"],
    qualities: ["minor", "minor", "dominant7", "major"]
  },
  "thelonious": {
    key: "Ambiguous/floating",
    bpm: 92,
    progression: ["Ebm", "Bbm"], // non-resolving two-chord loop
    roman: ["i", "v"],
    qualities: ["minor", "minor"],
    note: "Two-chord loop that never resolves - creates floating feel"
  },
  "selfish": {
    key: "G major",
    bpm: null,
    progression: ["Cmaj7", "Bm7", "Am7", "D7"],
    roman: ["IVmaj7", "iii7", "ii7", "V7"],
    qualities: ["major7", "minor7", "minor7", "dominant7"]
  }
};
```

```ruby
fantastic_vol1 = {
  look_of_love: {
    key: "G major",
    progression: ["Bm7", "Bm7", "Cmaj7", "Em7"],
    roman: ["iii7", "iii7", "IVmaj7", "vi7"],
    qualities: ["minor7", "minor7", "major7", "minor7"],
    sample_source: "Inside My Love - Minnie Riperton"
  }
}
```

**Donuts (2006) - Key tracks**

```javascript
const donuts = {
  "time_donut_of_the_heart": {
    key: "Ab major / F minor",
    bpm: 94,
    progression: ["Dbmaj7", "Cm7", "Fm7", "Bbm7"],
    roman: ["IVmaj7", "iii7", "vi7", "ii7"],
    qualities: ["major7", "minor7", "minor7", "minor7"],
    sample: "All I Do Is Think of You - Jackson 5 (slowed to half-speed)"
  },
  "workinonit": { key: "B minor", bpm: 93 },
  "lightworks": { key: "F# minor", bpm: 95 },
  "dont_cry": { key: null, bpm: 87 },
  "waves": { key: "A# minor", bpm: 90 },
  "stop": { key: "F# minor", bpm: 86 }
};
```

### Mixing approach and lo-fi aesthetic

Dilla achieved his signature warmth through **aggressive low-pass filtering** (removing high frequencies from samples), the inherent **12-bit character** of the SP-1200, and **sub-bass enhancement** using an oscillator at ~40Hz triggered by kick drums through a gate with very short release. Engineer Bob Power used the **Yamaha SPX900's "Symphonic" program with D-filter** for the "watery, bubbly" sample processing heard on many Dilla productions.

---

## Flying Lotus: Jazz lineage meets electronic experimentation

Steven Ellison's connection to Alice Coltrane (his great-aunt) and grandmother Marilyn McLeod (Motown songwriter of "Love Hangover") positioned him uniquely between jazz heritage and electronic production. The **Los Angeles album (2008)** established his signature sound: hazy textures, off-kilter rhythms, and layered sonic collages.

### Equipment and software (2006-2008 era)

**DAW:** Reason (primary during 1983/Los Angeles era), later transitioned to Ableton Live

**Hardware:** Roland MC-505 Groovebox (first production tool, gift from cousin Oran Coltrane), Boss SP-303 Dr. Sample (used on "Testament," "Between Friends"), M-Audio Trigger Finger, Akai MPD32, Akai MPK49

**Later additions:** Access Virus TI, Minimoog Voyager, Moog Sub Phatty, Fender Rhodes, Wurlitzer, Roland Space Echo RE-201, Focal Twin6 Be monitors

### Los Angeles album production techniques

The album was recorded **September 2007 - March 2008** in Flying Lotus's apartment in the San Fernando Valley during what he described as "intensive lab sessions." The hazy, textured sound combines several techniques:

- **Vinyl noise layer:** High-pass filtered vinyl samples or iZotope Vinyl plugin
- **Pumping master compression:** Often sidechained to kick drum
- **SP-303/404 style compression:** Crunchy, lo-fi degradation
- **Pitch manipulation:** Samples pitched down to sound heavier

**Sidechain compression settings for the "FlyLo pump":**
- Attack: 0.75-1ms
- Release: 10-20ms  
- Ratio: High (near-limiting)
- Threshold: 30-40dB reduction

### Track analysis for Los Angeles

```javascript
const losAngelesAlbum = {
  "camel": {
    key: "C major",
    bpm: 84,
    camelot: "8B",
    timeSignature: "4/4",
    character: "Percussive, janky rhythm with eastern jangle elements"
  },
  "robertaflack": {
    key: "G major",
    bpm: 81,
    camelot: "9B",
    coproduction: ["Samiyam", "Byron the Aquarius"],
    character: "Laid-back jazz, lush neo-soul"
  },
  "gng_bng": {
    key: null,
    bpm: 103,
    coproduction: ["The Gaslamp Killer"],
    character: "Heavy, gangster film soundtrack, wall of noise approach",
    sample_reference: "Tamil film 'Uyirullavarai Usha'"
  },
  "riot": {
    key: null,
    bpm: null,
    duration: "4:02",
    character: "Heavy mood, darker intensity"
  }
};

// Album BPM range: 83-192 BPM, average 110 BPM
```

### Dilla influence on Flying Lotus

FlyLo adapted Dilla's timing approach: programming drums **without quantization**, nudging snares slightly early or late for that "lazy-yet-tight" feel, and pushing upbeat hi-hats behind the beat. Both producers use extensive sidechain compression to create the pumping, breathing quality in their mixes.

**Key difference:** Flying Lotus incorporates more IDM textures, explicit dubstep influence, and cosmic/space-age sound design while maintaining the jazz harmony from his family lineage. Alice Coltrane's harp playing directly influenced his use of cascading glissando sounds and extended jazz harmony.

---

## Madlib: The prolific crate-digger's philosophy

Otis Jackson Jr. represents a fundamentally different production philosophy: **speed over perfection**, triggering everything live rather than sequencing, and embracing lo-fi artifacts as intentional texture. He reportedly makes beats in **under 10-15 minutes** and works **10+ hours daily**, owning over **4 tons of vinyl** across multiple rooms.

### Complete equipment list

**Primary samplers:** Boss SP-303 "Dr. Sample" (signature unit—does NOT use sequencer, triggers all samples live into multitrack), E-mu SP-1200/SP-12 (12-bit at 26kHz), Roland SP-606

**Recording destinations:** Roland VS-1680 (16-track digital), Roland VS-880 (8-track, used for Jaylib), Tascam Portastudio 488 (cassette 8-track, used for Quasimoto's "The Unseen"), Tascam 388 reel-to-reel

**Keyboards:** Fender Rhodes Suitcase, Hohner Clavinet, RMI Electra-Piano, ARP String Ensemble, Korg MicroKorg, Roland Fantom G7

**Unconventional gear:** Fisher-Price children's turntable (used for Madvillainy sessions in Brazil), Apple iPad (used for entire Bandana album)

### SP-303 effects usage

| Effect | Application |
|--------|-------------|
| **Vinyl Sim** | Signature compression + crackle + wow/flutter |
| Wah-wah | Primary modulation effect |
| Time Stretch | Pitch shifting with intentional digital artifacts |
| Tape Echo | Vintage delay character |
| Phaser | Psychedelic textures |
| Ring Mod | Experimental sounds |

### Madvillainy production approach

The album was largely created in a **São Paulo hotel room** during a Red Bull Music Academy trip using only a **Boss SP-303, Fisher-Price turntable, and tape deck**. Madlib's quote: "Cuts like 'Raid' I did in my hotel room in Brazil on a portable turntable, my 303, and a little tape deck."

**Workflow:** SP-303 beats recorded to Roland VS-1680 → DOOM's vocals recorded "straight into a VS-880... no preamp or compressor" → Final mixing by Dave Cooley in Pro Tools

### Chord progressions and harmonic analysis

```ruby
madvillainy_chords = {
  accordion: {
    key: "D minor",
    bpm: 96,
    time_signature: "4/4",
    progression: ["Dm", "Gm", "Am"],
    roman: ["i", "iv", "v"],
    qualities: ["minor", "minor", "minor"],
    sample: "Daedelus - Experience (Magnus 391 Electric Chord Organ)",
    note: "Forms new arrangements throughout—not a simple loop"
  }
}
```

```javascript
const madlibHarmonicTendencies = {
  preferredKeys: "minor keys (melancholic, introspective)",
  chordTypes: ["minor7", "major7", "dominant7", "9th", "11th"],
  influences: ["Lonnie Liston Smith", "Elvin Jones", "Black Jazz catalog", "Strata East"],
  era: "1960s-70s jazz, soul, funk with future twist",
  pitchApproach: "Often pitches samples up/down using SP-303 time stretch—embraces detuned quality"
};
```

### Beat Konducta series techniques

The 8-album instrumental series features **short-form beats (30 seconds to 3 minutes)** presented as "beat tape productions in the style of 70s TV & film library music." Vol. 5-6 (Dil Cosby/Dil Withers Suite) is a J Dilla tribute with extensive soul, jazz, and funk samples.

### Lo-fi mixing aesthetic

Madlib's intentionally rough sound comes from:

- **Tascam cassette 8-track recording** adding natural compression and saturation
- **SP-303 "Vinyl Sim" effect** for compression, crackle, wow/flutter
- **Direct vinyl sampling** preserving surface noise
- **Minimal processing philosophy**—internal effects rather than outboard gear
- **Format bouncing** (cassette → digital → cassette) for added texture

Engineer Dave Cooley: "Madlib likes to shoot from the hip, so sometimes it's a deliberate and intentional choice on his part to go with the most rough-hewn version of a mix."

### Quasimoto vocal technique

The pitch-shifted "Lord Quas" voice is created by **slowing the beat down, rapping in normal voice at reduced pace, then speeding the tape back up**—resulting in the chipmunk-style pitch shift while maintaining intelligibility.

---

## Complete chord data for code implementation

```javascript
// Master chord progression database
const producerChords = {
  jDilla: {
    fantasticVol2: {
      fall_in_love: { key: "Fm", bpm: 91, chords: ["Bbm", "Ab", "Fm7", "Fm"] },
      climax: { key: "E", bpm: 96, chords: ["Emaj7", "G#m7", "G#m7", "G#maj7"] },
      get_dis_money: { key: "C#m", bpm: 90, chords: ["C#m", "G#m", "A#7", "C#"] },
      selfish: { key: "G", bpm: null, chords: ["Cmaj7", "Bm7", "Am7", "D7"] }
    },
    donuts: {
      time_donut: { key: "Ab", bpm: 94, chords: ["Dbmaj7", "Cm7", "Fm7", "Bbm7"] }
    },
    theShining: {
      so_far_to_go: { key: "Bb", bpm: null, chords: ["Dm7", "Cm7", "F", "Gm7"] }
    }
  },
  flyingLotus: {
    losAngeles: {
      camel: { key: "C", bpm: 84 },
      robertaflack: { key: "G", bpm: 81 },
      gng_bng: { key: null, bpm: 103 }
    }
  },
  madlib: {
    madvillainy: {
      accordion: { key: "Dm", bpm: 96, chords: ["Dm", "Gm", "Am"] }
    }
  }
};

// Timing/swing parameters for Dilla-style humanization
const dillaSwing = {
  mpcSwingRange: { min: 50, max: 75, sweetSpot: [53, 56] },
  goldenRatioSwing: 62.5,
  tempoRange: { min: 82, max: 92 },
  nudgeDirections: {
    hihats: "forward",  // ahead of beat
    snares: "early",    // push beat forward
    kicks: "late"       // laid-back contrast
  }
};
```

```ruby
# Ruby implementation
producer_chords = {
  j_dilla: {
    fantastic_vol2: [
      { track: "fall_in_love", key: "Fm", bpm: 91, 
        chords: %w[Bbm Ab Fm7 Fm], roman: %w[iv bIII i7 i] },
      { track: "climax", key: "E", bpm: 96,
        chords: %w[Emaj7 G#m7 G#m7 G#maj7], roman: %w[Imaj7 iii7 iii7 IIImaj7] },
      { track: "get_dis_money", key: "C#m", bpm: 90,
        chords: %w[C#m G#m A#7 C#], roman: %w[i v VI7 I] }
    ],
    donuts: [
      { track: "time_donut_of_the_heart", key: "Ab", bpm: 94,
        chords: %w[Dbmaj7 Cm7 Fm7 Bbm7], roman: %w[IVmaj7 iii7 vi7 ii7] }
    ]
  },
  madlib: {
    madvillainy: [
      { track: "accordion", key: "Dm", bpm: 96,
        chords: %w[Dm Gm Am], roman: %w[i iv v] }
    ]
  }
}

dilla_swing_params = {
  swing_percentage: (53..56),
  ppqn: 96,
  tempo_range: (82..92),
  nudge: { hihats: :forward, snares: :early, kicks: :late }
}
```

## Conclusion

These three producers share a commitment to **humanized machine music** and **lo-fi warmth**, but approach it from different angles. Dilla pioneered micro-timing manipulation on the MPC3000, creating grooves that feel simultaneously precise and loose. Flying Lotus inherited jazz harmony from his family lineage while pushing into electronic territory, using sidechain compression and textural layering to create hazy soundscapes. Madlib prioritizes workflow speed and raw authenticity, triggering everything live into multitrack recorders and embracing the SP-303's digital artifacts as intentional texture.

For code implementation, the key parameters are: **BPM ranges of 82-96** for that signature tempo pocket, **minor 7th and major 7th chord voicings** as the harmonic foundation, and **swing values between 53-62.5%** with individual element nudging for humanization. The lo-fi aesthetic comes from bit-depth reduction, tape saturation emulation, and aggressive low-pass filtering rather than pristine digital processing.