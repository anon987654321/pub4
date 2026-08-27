#!/usr/bin/env ruby
# frozen_string_literal: true

# The Colab side of the Colab lane. Everything the session does happens here.
#
# Colab runs Python notebooks, so the notebook cannot be Ruby — but it can be a
# handover, and this is what it hands over to. Same split as every other lane:
# Ruby owns the chain, Python appears only where ai-toolkit's run.py does.
#
# Why Colab at all: Kaggle gates both GPU and internet behind phone
# verification. An unverified account gets a CPU box with no network — measured,
# not assumed: a probe kernel reported torch 2.10.0+cpu, no nvidia-smi, no DNS,
# and no ruby. Colab's free tier asks for a Google account and nothing else.
#
# The GPU is the same 16 GB Turing T4 Kaggle would have given, so the cuda_t4
# profile in render_config.rb applies unchanged: fp16 because Turing has no
# bf16, quantised because 16 GB will not hold FLUX.1-dev otherwise.
#
# Invoked as:  ruby STUDIO/lora/_toolkit/colab_session.rb <subject>
# Expects:     HF_TOKEN in the environment, put there by the notebook

require "fileutils"
require "json"
require "rbconfig"
require "pathname"

SUBJECT = ARGV.fetch(0) { abort "warn: usage: colab_session.rb <subject>" }
REPO = Pathname.new(__dir__).join("../../..").expand_path
SUBJECT_DIR = REPO.join("STUDIO/lora", SUBJECT)
AI_TOOLKIT = Pathname.new(ENV.fetch("AI_TOOLKIT_ROOT", "/content/ai-toolkit"))

# Colab keeps nothing when the runtime recycles, and a free session is capped
# around 12 h with an idle disconnect well before that. Whatever is worth having
# after the tab closes goes to Drive, if the notebook mounted it.
PERSIST = Pathname.new(ENV.fetch("LORA_PERSIST_DIR", "/content/persist"))

IMAGE_EXT = %w[.jpg .jpeg .png .webp].freeze

# ai-toolkit saves as <name>_<step zero-padded to 9>.safetensors, and the name
# carries its own digits — ragnhild_v2_000001500 begins with a 2. Reading the
# first digit run scored every checkpoint identically and silently resumed from
# whichever had the newest mtime.
def step_of(path)
  path.basename.to_s[/(\d+)\.safetensors\z/, 1].to_i
end

def sh!(*command)
  puts "run: #{command.join(' ')}"
  return if system(*command)

  # A banner, because of where this output ends up. The notebook invokes this
  # script through subprocess.run(check=True), so a non-zero exit surfaces in
  # Colab as a CalledProcessError traceback with the Python frames of
  # subprocess.py in it and nothing about what actually failed. The real reason
  # is here, above that traceback, and it does not look like a heading — so
  # people paste the traceback and the traceback says only that ruby exited 1.
  #
  # The same shape as the Kaggle failure documented in lora/README.md, where
  # IPython's own formatter crashed while rendering a DNS error and buried it 80
  # lines up. Worth a marker anyone can search for.
  warn ""
  warn "=" * 72
  warn "FAILED: #{command.join(' ')}"
  warn "The Python traceback below this only reports that ruby exited non-zero."
  warn "The cause is the output ABOVE this banner."
  warn "=" * 72
  abort "warn: failed: #{command.join(' ')}"
end

def subject_env
  Hash[SUBJECT_DIR.join("subject.env").read.lines.filter_map do |line|
    key, value = line.strip.split("=", 2)
    [key, value] if value && !key.start_with?("#")
  end]
end

MODEL = subject_env.fetch("MODEL")
WEIGHTS_DIR = SUBJECT_DIR.join("weights", MODEL)
OUT_DIR = SUBJECT_DIR.join("out")

def prepare
  abort "warn: HF_TOKEN missing — the notebook did not set it" if ENV["HF_TOKEN"].to_s.strip.empty?
  ENV["HUGGINGFACE_HUB_TOKEN"] = ENV.fetch("HF_TOKEN")
  ENV["AI_TOOLKIT_ROOT"] = AI_TOOLKIT.to_s
  abort "warn: no subject at #{SUBJECT_DIR}" unless SUBJECT_DIR.directory?
  [WEIGHTS_DIR, PERSIST].each(&:mkpath)
  restrain_the_downloader
  add_swap
  drop_latent_cache
  puts "ok: subject #{SUBJECT} model #{MODEL}"
end

# The latents on disk remember which VAE made them. Nothing else does.
#
# cache_latents_to_disk writes one .npy beside each image the first time a run
# encodes it, and every later run reads it back. The cache key is the image —
# not the VAE, not the dtype, not the resolution the encoder was configured
# with. So a run that encoded through a broken VAE leaves broken latents, and
# the run that fixes the VAE never calls it.
#
# That is what happened here. SDXL's own VAE overflows fp16, the first run wrote
# NaN latents, and the two runs afterwards read NaN off disk at step one with
# vae_path: madebyollin/sdxl-vae-fp16-fix sitting correctly in the printed
# config. The tell was in the log the whole time: "Caching latents to disk:
# 7/7 [00:00<00:00, 4664.04it/s]". Encoding seven 768px images on a T4 takes
# a second or two. 1.5 milliseconds is a cache hit.
#
# Recomputing costs that same second or two, so there is nothing to weigh: drop
# it every run. At a dataset size where caching pays for itself, set
# LORA_KEEP_LATENT_CACHE and take responsibility for invalidating it.
CACHE_DIRNAME = "_latent_cache"

def drop_latent_cache
  return puts "note: keeping the latent cache (LORA_KEEP_LATENT_CACHE)" if ENV["LORA_KEEP_LATENT_CACHE"]

  cache = SUBJECT_DIR.join("dataset", CACHE_DIRNAME)
  return unless cache.directory?

  latents = cache.glob("**/*").count(&:file?)
  FileUtils.rm_rf(cache)
  puts "ok: dropped #{latents} cached latent(s) — they are re-encoded by whichever VAE this run configures"
end

# Somewhere for the checkpoint shards to go that is not RAM.
#
# The download finishes now and the run dies one step later, at "Loading
# checkpoint shards: 1/3". Same resource, different phase: FLUX.1-dev's weights
# are 23.8 GB of fp16 and they are read into SYSTEM memory before quantisation
# moves them to the card. A free Colab has 12.7 GB. It gets through the first
# shard and is killed on the second.
#
# quantize and low_vram do not help with this. Both govern what ends up in VRAM,
# and the ceiling being hit is host RAM during load — the model has to be
# materialised before it can be made smaller.
#
# So: give the kernel a swapfile on the 100 GB scratch disk. The loader spills
# instead of being killed, which is slow — reading weights back off disk once —
# and it is the difference between a run and no run. 24 GB because the shards
# total 23.8, and there is no benefit to being exact.
#
# Guarded rather than assumed. Colab happens to run as root and permit swapon;
# a container that does not will fail here harmlessly, and the failure is worth
# printing because it turns the next OOM from a mystery into a known cause.
SWAP_PATH = "/content/swapfile"
SWAP_SIZE = "24G"

def add_swap
  return puts "note: swap already active" if `swapon --show 2>/dev/null`.include?("/")

  ok = system("fallocate", "-l", SWAP_SIZE, SWAP_PATH, out: File::NULL, err: File::NULL) &&
       system("chmod", "600", SWAP_PATH, out: File::NULL, err: File::NULL) &&
       system("mkswap", SWAP_PATH, out: File::NULL, err: File::NULL) &&
       system("swapon", SWAP_PATH, out: File::NULL, err: File::NULL)

  if ok
    puts "note: #{SWAP_SIZE} of swap at #{SWAP_PATH}. FLUX's shards are 23.8 GB of fp16 and"
    puts "note: are read into host RAM before quantisation; this box has 12.7 GB."
  else
    FileUtils.rm_f(SWAP_PATH)
    puts "warn: could not enable swap — the loader may be killed at 'Loading checkpoint"
    puts "warn: shards'. That is host RAM, not VRAM, and quantize/low_vram do not help."
  end
end

# Download FLUX.1-dev without exhausting the machine's memory.
#
# The run that got this far died mid-download at 12.6 GB of 23.8 GB, and Colab's
# log recorded it honestly: `AsyncIOLoopKernelRestarter: restarting kernel`. Not
# a crash in training, not a bad weight — the kernel was killed, and 12.6 GB is
# what a free Colab has of system RAM.
#
# hf-xet is the reason. It is a deduplicating transfer that fetches content
# chunks and REASSEMBLES them in memory, which is what the "Reconstructing
# (incomplete total...)" progress bars in the log are. Alongside hf_transfer's
# parallel connections it saturates the link beautifully and needs headroom
# proportional to the file. FLUX.1-dev is larger than this box's RAM, so the
# fast path cannot finish on the tier this lane exists to use.
#
# Both off. The plain downloader streams to disk and holds a buffer rather than
# a file, so the ceiling becomes the 100 GB of scratch instead of 12.7 GB of
# RAM. It is slower and it completes, which beats fast and killed.
#
# The cache goes to /content too. It defaults under ~/.cache, and on a runtime
# whose home is small a 24 GB download can fill the wrong filesystem — same
# failure, different resource, and much harder to read from the log.
def restrain_the_downloader
  ENV["HF_HUB_DISABLE_XET"] = "1"
  ENV["HF_HUB_ENABLE_HF_TRANSFER"] = "0"
  ENV["HF_HOME"] ||= "/content/hf_cache"
  FileUtils.mkdir_p(ENV["HF_HOME"])
  # Says what it SETS, not what it achieves.
  #
  # It used to announce "xet and hf_transfer disabled ... Slower, and it
  # finishes" — three claims, and the run disproved all three. The
  # "Reconstructing (incomplete total...)" bars appeared exactly as before, so
  # HF_HUB_DISABLE_XET did not take; the download was no slower; and the run did
  # not finish. A message that reports an intention in the past tense is worse
  # than no message, because the next reader takes it as evidence and looks
  # somewhere else for the cause.
  #
  # The variables stay because they are correct to set and cost nothing. What
  # changed is that this no longer claims they worked.
  puts "note: requested HF_HUB_DISABLE_XET=1 and HF_HUB_ENABLE_HF_TRANSFER=0."
  puts "note: xet has ignored this before — if you still see 'Reconstructing'"
  puts "note: progress bars below, it did, and the transfer is still the fast path."
  puts "note: model cache at #{ENV['HF_HOME']}"
end

# Can the toolkit actually run, as opposed to having been downloaded?
#
# The guard here used to be `.git exists`, and that is a fact about the clone
# rather than about the install. A session that cloned and then died — a pip
# failure, a runtime recycle, a closed tab — left a directory with .git in it
# and no dependencies, and every retry afterwards printed "ok: ai-toolkit
# already present" and went straight to training, where run.py died on its third
# line importing dotenv. The step that would have fixed it was the step being
# skipped, so the failure was perfectly repeatable and its cause was three lines
# above it saying everything was fine.
#
# Asked of the venv instead, which is where the answer lives: import the things
# run.py imports first. dotenv is what it actually failed on; torch and
# safetensors cost nothing extra to check and fail earlier if the venv was built
# against the wrong interpreter.
TOOLKIT_SENTINELS = "import dotenv, torch, safetensors, transformers"

def toolkit_ready?
  python = AI_TOOLKIT.join(".venv/bin/python")
  return false unless python.file?

  system(python.to_s, "-c", TOOLKIT_SENTINELS, out: File::NULL, err: File::NULL)
end

# A venv with pip in it, by whichever route works.
#
# `python3 -m venv` is not self-contained on Debian. The stdlib is split into
# packages and venv's bootstrap step, ensurepip, ships separately — so on an
# image without python3-venv the command creates the directory, reaches
# ensurepip, and exits 1 reporting the name of the subprocess that failed rather
# than the name of the package that is missing. It reads as a Python fault and
# is an apt one.
#
# The notebook installs python3-venv now, which should make the first branch
# work. This exists because that is a fix in a different file: a notebook
# regenerated from an older run_train_colab.rb, or any host whose image differs,
# lands back here. virtualenv carries its own pip and needs no stdlib package,
# so it works where venv does not.
def make_venv(path)
  return puts "ok: venv already at #{path}" if path.join("bin/python").file?

  puts "run: python3 -m venv --system-site-packages #{path}"
  return puts "ok: venv created" if system("python3", "-m", "venv", "--system-site-packages", path.to_s)

  puts ""
  puts "note: `python3 -m venv` failed. On Debian that is usually python3-venv"
  puts "note: missing rather than anything wrong with Python — ensurepip lives in"
  puts "note: that package. Falling back to virtualenv, which bundles its own pip."
  FileUtils.rm_rf(path)
  sh!("python3", "-m", "pip", "install", "-q", "--upgrade", "virtualenv")
  sh!("python3", "-m", "virtualenv", "--system-site-packages", path.to_s)
  puts "ok: venv created by virtualenv"
end

def install_ai_toolkit
  return puts "ok: ai-toolkit present and importable" if toolkit_ready?

  if AI_TOOLKIT.join(".git").directory?
    puts "note: ai-toolkit is cloned but its dependencies do not import — installing"
  else
    sh!("git", "clone", "--depth", "1", "https://github.com/ostris/ai-toolkit.git", AI_TOOLKIT.to_s)
  end
  # Colab's own torch is CUDA-matched to its driver; a clean venv would pull a
  # second multi-GB one off PyPI that is not. run_ai_toolkit.rb requires a venv
  # python, so it stays a venv — one that can see the image's packages.
  make_venv(AI_TOOLKIT.join(".venv"))
  pip = AI_TOOLKIT.join(".venv/bin/pip").to_s
  sh!(pip, "install", "-q", "--upgrade", "pip", "wheel")

  install_requirements(pip)
end

# Exact pins that predate the interpreter Colab now ships.
#
# ai-toolkit pins these to a single version, and none of those versions
# publishes a cp313 wheel. On Colab's Python 3.13 pip therefore falls back to
# building from source, which for scipy wants a Fortran toolchain that is not
# on the image. The pin is the problem, not the package: every one of these has
# a later release that installs cleanly.
#
# Relaxed to a floor rather than removed, so pip still refuses a version older
# than the one the toolkit was written against.
STALE_PINS = %w[scipy albumentations albucore optimum-quanto torchao].freeze

# Install, and if an exact pin is what stopped it, relax those pins and say so.
#
# Deliberately a fallback rather than the first attempt. The pins are the
# author's intent and they may matter; trying them first means an environment
# where they work gets what ai-toolkit asked for. Only when that fails does this
# trade an exact version for an install that exists at all — and it prints what
# it changed, because a silent version substitution in a training pipeline is
# the kind of thing that surfaces three hours later as a strange loss curve.
def install_requirements(pip)
  requirements = AI_TOOLKIT.join("requirements.txt")
  puts "run: #{pip} install -r #{requirements} (verbose; several pins predate Colab's Python 3.13)"
  return puts "ok: requirements installed as pinned" if system(pip, "install", "-r", requirements.to_s)

  relaxed = relax_pins(requirements)
  puts ""
  puts "note: the pinned install failed. Retrying with these exact pins relaxed to floors:"
  puts "note:   #{STALE_PINS.join(', ')}"
  puts "note: none of them publishes a wheel for Python 3.13, which is what Colab runs."
  sh!(pip, "install", "-r", relaxed.to_s)
  puts "ok: requirements installed with #{STALE_PINS.length} pin(s) relaxed"
end

# Flatten the -r includes, then relax. Both halves are necessary.
#
# requirements.txt opens with `-r requirements_base.txt` and holds exactly one
# stale pin of its own; the other four are in that base file. So relaxing only
# the top-level file misses four of the five. And a relaxed copy written
# somewhere else keeps the `-r requirements_base.txt` line, which pip resolves
# relative to the file it is reading — so the copy would look for a base file
# that is not beside it and fail on something unrelated to the pins.
#
# Inlining the includes solves both: one flat file, every pin visible, no
# relative reference left to break. Written into the toolkit directory anyway,
# so anything else in there resolving by relative path still does.
def relax_pins(requirements, depth = 0)
  out = AI_TOOLKIT.join("requirements_relaxed.txt")
  out.write(flatten_requirements(requirements).map { |line| relax_line(line) }.join)
  out
end

def flatten_requirements(path, seen = [])
  return [] if seen.include?(path.to_s) || seen.length > 8

  seen << path.to_s
  path.readlines.flat_map do |line|
    include = line[/\A\s*-r\s+(\S+)/, 1]
    next [line] unless include

    nested = path.dirname.join(include)
    nested.file? ? ["# inlined from #{include}\n", *flatten_requirements(nested, seen)] : [line]
  end
end

def relax_line(line)
  name = line[/\A\s*([A-Za-z0-9_.\-]+)\s*==/, 1]
  return line unless name && STALE_PINS.include?(name.downcase)

  line.sub("==", ">=")
end

# A checkpoint saved to Drive last session is the only reason a second session
# is cheaper than a first. ai-toolkit resumes from the newest save in the
# training folder, reading the step back out of the safetensors metadata.
# Does this checkpoint contain NaN?
#
# A run whose loss went NaN still writes checkpoints on schedule — the save code
# does not inspect what it is saving. Those files then sit in Drive and the next
# session resumes from them, which poisons a run that was otherwise fixed. That
# happened here: the VAE fix landed, the run restarted, and it resumed from
# step 750 of the dead run.
#
# safetensors is readable without a library: 8 bytes of little-endian header
# length, then that many bytes of JSON naming every tensor with its dtype and
# byte range, then the raw data. Enough to sample one tensor and look at it.
#
# float16 is NaN when the five exponent bits are all set and the mantissa is
# not zero — (bits & 0x7C00) == 0x7C00 && (bits & 0x03FF) != 0. Checking a few
# thousand values from each of a few tensors is plenty: a NaN checkpoint is not
# subtly NaN, it is comprehensively NaN.
SAMPLE_VALUES = 4096

def each_sampled_tensor(path)
  File.open(path, "rb") do |file|
    header_length = file.read(8)&.unpack1("Q<")
    return unless header_length&.positive? && header_length < 100_000_000

    header = JSON.parse(file.read(header_length).to_s)
    body = 8 + header_length

    header.each do |name, spec|
      next if name == "__metadata__"
      next unless spec.is_a?(Hash) && spec["dtype"] == "F16"

      start, finish = spec["data_offsets"]
      next unless start && finish && finish > start

      file.seek(body + start)
      yield name, file.read([finish - start, SAMPLE_VALUES * 2].min).to_s.unpack("v*")
    end
  end
end

def checkpoint_nan?(path)
  seen = 0
  each_sampled_tensor(path) do |_name, values|
    return true if values.any? { |bits| (bits & 0x7C00) == 0x7C00 && (bits & 0x03FF) != 0 }

    seen += 1
    break if seen >= 4
  end
  false
# Narrow on purpose. `rescue StandardError` here caught NameError from a missing
# `require "json"` and reported it as an uninspectable file, so the guard was
# inert from the moment it shipped and said "ok:" while doing nothing. A
# malformed file is a thing to shrug at; a bug in this method is not.
rescue IOError, SystemCallError, JSON::ParserError => e
  warn "note: could not inspect #{path.basename} (#{e.class}: #{e.message}); resuming anyway"
  false
end

# Has this checkpoint learned anything, whatever its filename claims?
#
# A NaN loss produces no gradient and ai-toolkit skips the step rather than
# applying it, so the weights never move. The saver does not know that: it writes
# ragnhild_v2_000000750.safetensors on schedule, the metadata says step 750, and
# the next session resumes from it and trains the remaining 250 steps believing
# it is finishing a run that never started. That produced the first real
# portraits of Ragnhild off a quarter of the intended training.
#
# It is visible in the weights. A LoRA is a pair per module — down initialised
# random, up initialised to zeros so the adapter is a no-op before training. Only
# training moves the up side off zero. So an all-zero up side means untrained,
# regardless of what the step counter says.
#
# Sampled across several modules because one all-zero tensor could be an honestly
# dead module; every up tensor being zero could not.
UP_TENSOR = /lora_up|lora_B/
UP_TENSORS_TO_CHECK = 8

def checkpoint_untrained?(path)
  ups = 0
  each_sampled_tensor(path) do |name, values|
    next unless name.match?(UP_TENSOR)

    # 0x7FFF masks the sign, so -0.0 still counts as zero.
    return false if values.any? { |bits| (bits & 0x7FFF) != 0 }

    ups += 1
    break if ups >= UP_TENSORS_TO_CHECK
  end
  ups.positive?
rescue IOError, SystemCallError, JSON::ParserError
  false
end

def restore_checkpoints
  saved = PERSIST.glob("*.safetensors").sort
  return puts "ok: no checkpoint to resume from" if saved.empty?

  # Newest first, and skip any that is NaN. A poisoned checkpoint makes the
  # session that resumes from it fail identically to the session that wrote it,
  # which is how a fixed pipeline keeps looking broken.
  ordered = saved.sort_by { |path| [-step_of(path), -path.mtime.to_i] }
  rejected = []

  ordered.each do |path|
    if checkpoint_nan?(path)
      rejected << [path, "NaN weights"]
      next
    end
    if checkpoint_untrained?(path)
      rejected << [path, "untrained — every LoRA up tensor is still zero"]
      next
    end

    unless rejected.empty?
      puts "warn: skipped #{rejected.length} checkpoint(s) that cannot be resumed from:"
      rejected.each { |bad, why| puts "warn:   #{bad.basename} — #{why}" }
      puts "warn: these came from a run whose loss had already collapsed. Their step"
      puts "warn: numbers are real; the training behind those steps is not."
      puts "warn: delete them from #{PERSIST} once you are sure."
    end
    # Not assumed to exist. LORA_COLAB_STAGES lets any stage run on its own, and
    # the directory is only created by prepare, so `restore` alone died on ENOENT
    # from inside FileUtils with a stack trace and no line of its own.
    WEIGHTS_DIR.mkpath
    FileUtils.cp(path, WEIGHTS_DIR.join(path.basename))
    return puts "ok: resuming from #{path.basename}"
  end

  puts "warn: all #{rejected.length} checkpoint(s) in #{PERSIST} are NaN or untrained."
  puts "warn: starting from scratch rather than resuming from a dead run."
end

# Stop the run the moment the loss stops being a number.
#
# A NaN gradient updates nothing, so training continues at full speed, the
# progress bar advances, checkpoints are written on schedule, and the adapter
# inside them is untrained. One run reached step 500 and generated twelve
# validation images off a dead LoRA before anyone could see the problem — an
# hour of a free GPU session spent producing plain SDXL.
#
# ai-toolkit prints "loss is nan" per occurrence and carries on. That is a
# reasonable default for a transient spike; it is the wrong one for a schedule
# that has collapsed, and the two look identical for the first few lines. Ten
# consecutive is not a spike.
NAN_TOLERANCE = 10

def watch_for_nan(line, state)
  if line.include?("loss is nan")
    state[:nan] += 1
    if state[:nan] == NAN_TOLERANCE
      warn ""
      warn "=" * 72
      warn "ABORTING: #{NAN_TOLERANCE} consecutive NaN losses. Nothing is being learned."
      warn "A NaN gradient updates no weights, so this would run to completion and"
      warn "save checkpoints containing an untrained adapter."
      warn ""
      warn "On SDXL under fp16 the source is the VAE: SDXL was trained in"
      warn "fp32/bf16 and its VAE overflows fp16. render_config.rb sets"
      warn "vae_path to madebyollin/sdxl-vae-fp16-fix for exactly this."
      warn ""
      warn "If that override IS in the config above and you are still here, the"
      warn "NaN is not being produced now — it is being read off disk. Check the"
      warn "latent-caching line: seven images at 768px take a second or two to"
      warn "encode on a T4, so a rate in the thousands per second means nothing"
      warn "was encoded and the cache is from an earlier, broken run. prepare"
      warn "drops that cache every run; LORA_KEEP_LATENT_CACHE turns it off."
      warn "=" * 72
      return false
    end
  else
    state[:nan] = 0
  end
  true
end

# A resume that starts at the step ceiling trains nothing and says so nowhere.
#
# ai-toolkit reads the step out of the checkpoint metadata and begins there. If
# that number is already LORA_STEPS the loop has no iterations left: it loads the
# model, samples, saves, and exits — a full run's worth of output with no
# gradient in it. The log line is "Found step 1000 in metadata, starting from
# there" and it looks exactly like a healthy resume.
#
# It happened immediately after the untrained-checkpoint guard started working.
# The guard correctly rejected the three NaN-era files and fell through to
# ragnhild_v2.safetensors, which IS trained — 250 real steps — but carries step
# 1000, because the dead run's 750 skipped steps still counted. Every guard so
# far has been about whether a checkpoint learned anything; this is about whether
# there is anything left to learn.
#
# Reading the metadata rather than the filename, because the file that caused
# this has no step in its name at all.
def checkpoint_step(path)
  each_sampled_tensor(path) { break } # opens and validates the header
  header = File.open(path, "rb") do |file|
    length = file.read(8).unpack1("Q<")
    JSON.parse(file.read(length))
  end
  meta = header["__metadata__"] or return nil
  value = meta["training_step"] || meta["step"] || meta["steps"]
  value && Integer(value, exception: false)
rescue IOError, SystemCallError, JSON::ParserError
  nil
end

def warn_if_already_at_ceiling
  ceiling = Integer(ENV["LORA_STEPS"], exception: false) or return
  resumable = WEIGHTS_DIR.glob("**/*.safetensors")
                         .reject { |p| checkpoint_nan?(p) || checkpoint_untrained?(p) }
  reached = resumable.filter_map { |p| checkpoint_step(p) || (s = step_of(p)).positive? && s }.max
  return unless reached && reached >= ceiling

  warn ""
  warn "=" * 72
  warn "REFUSING: the checkpoint resumes at step #{reached} and LORA_STEPS is #{ceiling}."
  warn ""
  warn "There are no steps left to run. This would load the model, cache latents,"
  warn "save the same weights back and exit — no training, and no images either,"
  warn "because skip_first_sample means nothing samples until a step completes."
  warn "It takes about ten minutes and produces nothing, and the log reads like a"
  warn "normal run. That has now happened once."
  warn ""
  warn "Pick one:"
  warn "  LORA_STEPS=#{reached + 1000}   continue training, keeping what is learnt"
  warn "  clear #{PERSIST}   start over"
  warn "  LORA_COLAB_STAGES=prepare,generate,harvest   just render from this adapter"
  warn "=" * 72
  abort "warn: nothing to train"
end

def train
  ENV["LORA_DEVICE"] = "cuda_t4"
  ENV["LORA_SKIP_POSTPRO"] = "1"
  ENV["LORA_STEPS"] = ENV["LORA_STEPS"].to_s.strip.empty? ? "1800" : ENV["LORA_STEPS"]
  warn_if_already_at_ceiling
  ENV["LORA_SAMPLE_EVERY"] = ENV["LORA_SAMPLE_EVERY"].to_s.strip.empty? ? "500" : ENV["LORA_SAMPLE_EVERY"]
  # Piped rather than system(), so watch_for_nan can see the loss. The output is
  # re-printed unchanged, so this costs nothing except the ability to stop.
  command = ["sh", SUBJECT_DIR.join("lora").to_s, "--train"]
  puts "run: #{command.join(' ')}"
  state = { nan: 0 }
  ok = Dir.chdir(SUBJECT_DIR) do
    IO.popen(command, err: %i[child out]) do |io|
      io.each_line do |line|
        print line
        $stdout.flush
        unless watch_for_nan(line, state)
          Process.kill("TERM", io.pid) rescue nil
          return abort("warn: aborted on NaN loss")
        end
      end
    end
    $?.success?
  end
  abort "warn: failed: #{command.join(' ')}" unless ok
end

# Render the fifty sittings from a checkpoint that already exists.
#
# Training samples its twelve validation prompts as it goes, which is how the
# first portraits arrived without a second GPU. But the twelve are chosen to
# disagree with each other — they are a likeness diagnostic, not a record — and
# the fifty in shoots.yml are the actual deliverable.
#
# Separated from train because it is a different economics. Training is thirty
# minutes and produces one adapter; this is a sampling pass against an adapter
# that already exists, roughly thirty seconds a sitting on a T4, and it can be
# re-run as many times as there are ideas without touching the weights.
#
# LORA_PROMPT_SET narrows it — a side, or specific numbers — because fifty at
# once is twenty-five minutes and a bad seed is worth finding in three.
def generate
  ENV["LORA_DEVICE"] = "cuda_t4"
  ENV["LORA_SKIP_POSTPRO"] = "1"
  ENV["LORA_PROMPT_SET"] = ENV["LORA_PROMPT_SET"].to_s.strip.empty? ? "shoots" : ENV["LORA_PROMPT_SET"]

  weights = WEIGHTS_DIR.glob("*.safetensors")
  if weights.empty?
    abort "warn: no checkpoint in #{WEIGHTS_DIR} — run the train stage first, or " \
          "put one in #{PERSIST} for restore to pick up"
  end

  usable = weights.reject { |path| checkpoint_nan?(path) || checkpoint_untrained?(path) }
  if usable.empty?
    abort "warn: every checkpoint in #{WEIGHTS_DIR} is NaN or untrained. Rendering " \
          "from one would produce fifty pictures of the base model, not of #{SUBJECT}."
  end

  puts "ok: rendering set #{ENV['LORA_PROMPT_SET']} from #{usable.max_by { |p| step_of(p) }.basename}"
  sh! "sh", SUBJECT_DIR.join("lora").to_s, "--generate"
end

# Say which frames are worse than a real photograph, on the way past.
#
# Waxy skin, blown highlights and a plastic sheen arrive as finished JPEGs
# alongside the good ones and raise nothing. Until now the only thing that caught
# them was somebody scrolling a folder, which is how twelve portraits rendered on
# a mismatched sampler were looked at three times before anyone said "blurry".
#
# Reports, never blocks. The thresholds are calibrated from seven dim phone
# photographs, so they are a floor rather than a standard, and a frame that took
# thirty seconds of GPU is worth keeping even when four numbers disagree with it.
# --quarantine on judge.rb itself is the destructive-ish option, and it moves.
def judge_portraits
  judge = Pathname.new(__dir__).join("judge.rb")
  return unless judge.file? && OUT_DIR.directory?

  puts "run: judging #{OUT_DIR.basename} against the reference envelope"
  system(RbConfig.ruby, judge.to_s, OUT_DIR.to_s)
end

# The adapter and the validation portraits are the deliverables. ai-toolkit
# samples the curated prompt suite as it trains, so a training run is also the
# generate run — which is why this lane needs no paid one to see a face.
def harvest
  checkpoints = WEIGHTS_DIR.glob("*.safetensors").sort
  portraits = OUT_DIR.directory? ? OUT_DIR.children.select { |p| IMAGE_EXT.include?(p.extname.downcase) }.sort : []
  (checkpoints + portraits).each { |path| FileUtils.cp(path, PERSIST.join(path.basename)) }

  puts "ok: #{checkpoints.length} checkpoint(s) and #{portraits.length} portrait(s) in #{PERSIST}"
  judge_portraits
  abort "warn: training produced no .safetensors" if checkpoints.empty?
end

STAGES = {
  "prepare" => -> { prepare }, "install" => -> { install_ai_toolkit },
  "restore" => -> { restore_checkpoints }, "train" => -> { train },
  "generate" => -> { generate }, "harvest" => -> { harvest }
}.freeze

ENV.fetch("LORA_COLAB_STAGES", STAGES.keys.reject { |s| s == "generate" }.join(",")).split(",").each do |stage|
  STAGES.fetch(stage.strip) { abort "warn: no stage #{stage}" }.call
end
puts "ok: session complete"
