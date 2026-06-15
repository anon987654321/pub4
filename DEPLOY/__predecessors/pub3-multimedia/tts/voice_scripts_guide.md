# 🎙️ TTS Voice Scripts Collection
All your text-to-speech voice scripts with different effects and styles!
---
## 📋 Available Voice Scripts
### 1. **Natural Soft Voice** 👩
**File:** `natural_talk.rb`

**Command:** `ruby natural_talk.rb`

**Features:**
- Soft British female voice

- Slow, gentle speech

- Calming and peaceful messages

- Uses Google TTS with UK accent

---
### 2. **Deep Dark Male Voice** 👨
**File:** `deep_voice.rb`

**Command:** `ruby deep_voice.rb`

**Features:**
- Deep Australian male voice

- Normal speed, very dark tone

- Pitch lowered by 6 semitones

- Bass boost for rich sound

- Commanding and masculine

---
### 3. **Autotune Voice** 🎤
**File:** `autotune_voice.rb`

**Command:** `ruby autotune_voice.rb`

**Features:**
- T-Pain style autotune

- Tremolo (vibrato effect)

- Chorus (thick vocal layers)

- Reverb (concert hall echo)

- Echo/delay effects

- Musical/singing sound

---
### 4. **Vocoder Robot Voice** 🤖
**File:** `vocoder_voice.rb`

**Command:** `ruby vocoder_voice.rb`

**Features:**
- Daft Punk style robot voice

- Overdrive + synth

- Phaser effect

- Metallic/mechanical sound

- Pure sci-fi robot

---
### 5. **Joke-Telling Bot** 😂
**File:** `joke_talk.rb`

**Command:** `ruby joke_talk.rb`

**Features:**
- 50+ programming jokes

- Continuous comedy

- Natural voice

- Funny reactions

---
### 6. **Two-Way Voice Chat** 🎤💬
**File:** `voice_chat.rb`

**Command:** `ruby voice_chat.rb`

**Features:**
- Listens to your microphone

- Converts speech to text

- Responds with natural voice

- Real conversation!

**Requirements:** Termux:API app from F-Droid
---
## 🔧 Background Service Scripts
### Start Background Talking
**File:** `background_talk.sh`

**Command:** `~/background_talk.sh`

Keeps talking even when you leave Termux!
### Stop Background Talking
**File:** `stop_talk.sh`

**Command:** `~/stop_talk.sh`

Stops the background service.
---
## 🎛️ Voice Effects Breakdown
| Effect | What It Does |
|--------|--------------|

| **Pitch Shift** | Makes voice higher or lower |

| **Bass Boost** | Adds depth and richness |

| **Tremolo** | Wobbling/vibrato effect |

| **Chorus** | Layered vocal thickness |

| **Reverb** | Echo/space effect |

| **Echo** | Repeating delay |

| **Overdrive** | Distortion/grit |

| **Phaser** | Sweeping filter effect |

| **Vocoder** | Robotic synthesis |

---
## 🚀 Quick Start Commands
```bash
# Soft gentle female voice

ruby natural_talk.rb

# Deep commanding male voice
ruby deep_voice.rb

# Autotune T-Pain style
ruby autotune_voice.rb

# Robot vocoder voice
ruby vocoder_voice.rb

# Joke comedy bot
ruby joke_talk.rb

# Voice chat (needs Termux:API)
ruby voice_chat.rb

# Run in background
~/background_talk.sh

# Stop background
~/stop_talk.sh

```

---
## 🛠️ Dependencies Installed
- ✅ Python 3
- ✅ gTTS (Google Text-to-Speech)

- ✅ play-audio

- ✅ sox (audio effects)

- ✅ mpg123 (audio player)

- ✅ pulseaudio

- ✅ espeak (fallback)

- ✅ Termux:API (for mic input)

---
## 💡 Tips
1. **Stop any script:** Press `Ctrl+C`
2. **Kill all Ruby processes:** `pkill -9 ruby`

3. **Clear voice cache:** `rm -rf ~/.tts_cache*`

4. **Check what's running:** `ps aux | grep ruby`

---
## 🎨 Customization Ideas
Want to modify voices? Edit these parameters:
### In natural_talk.rb:
- Change `tld='co.uk'` to `tld='com.au'` for Australian

- Change `slow=True` to `slow=False` for normal speed

### In deep_voice.rb:
- Change `pitch -600` to `-800` for even deeper

- Add `tempo 0.9` for slower speech

### In autotune_voice.rb:
- Adjust `tremolo 5 0.8` - first number = speed, second = intensity

- Adjust `reverb 50` - higher = more echo

### In vocoder_voice.rb:
- Adjust `overdrive 15 15` for more distortion

- Change `tremolo 30 0.5` for different robot effect

---
## 📝 Created Scripts Summary
| Script | Style | Speed | Accent | Special Effects |
|--------|-------|-------|--------|-----------------|

| natural_talk.rb | Female | Slow | British | Gentle, calming |

| deep_voice.rb | Male | Normal | Australian | -6 semitones, bass |

| autotune_voice.rb | Unisex | Normal | American | Tremolo, chorus, reverb |

| vocoder_voice.rb | Robot | Normal | Synthesized | Overdrive, phaser |

| joke_talk.rb | Unisex | Normal | American | Comedy content |

| voice_chat.rb | Interactive | Normal | American | Microphone input |

---
**Enjoy your TTS voice collection!** 🎙️✨
Generated with Claude Code
