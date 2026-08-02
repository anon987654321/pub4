#!/usr/bin/env ruby
# frozen_string_literal: true

# Third train lane: Kaggle Notebooks. 30 GPU-hours a week, free, on a 16 GB T4.
#
# The split is the same one the rest of studio/lora keeps — Ruby owns the whole
# chain and Python appears only where the trainer does. Here Ruby packages the
# dataset, generates the notebook and its metadata, pushes, polls, and pulls the
# weights back; the notebook it generates is a shim that installs Ruby and hands
# straight back to run_generate.sh --train on the Kaggle box.
#
# Two things Kaggle imposes that the other lanes do not:
#
#   A GPU session is capped at 12 h and the weekly quota at ~30 h, so an 1800
#   step run is several sessions. Checkpoints ride between them in the dataset:
#   each run uploads the .safetensors it pulled last time, the notebook copies
#   them into weights/ before training, and ai-toolkit resumes from the newest.
#
#   /kaggle/working is capped at 20 GB and FLUX.1-dev is larger than that, so
#   the model cache goes to /kaggle/tmp (~60 GB, discarded at session end) and
#   only the LoRA — a few hundred MB at rank 32 — is written to the output.
#
# Usage:
#   ./lora --train-kaggle
#   ./lora --train-kaggle --dry-run
#   ./lora --train-kaggle --async
#   ./lora --train-kaggle --steps 600 --accelerator NvidiaTeslaP100
#
# Env:
#   KAGGLE_USERNAME + KAGGLE_KEY, or ~/.kaggle/kaggle.json
#   LORA_KAGGLE_USER        override the resolved Kaggle username
#   LORA_KAGGLE_STEPS       default 1800 (the full run; lower it per session)
#   LORA_KAGGLE_ACCELERATOR default NvidiaTeslaT4
#   LORA_KAGGLE_SECRET      notebook secret holding the HF token, default HF_TOKEN
#   LORA_KAGGLE_TIMEOUT     kernel wall clock, seconds, default 32400 (9 h)
#   LORA_KAGGLE_POLL        status poll interval, seconds, default 120
#   PUB4_REPO / PUB4_BRANCH the checkout the notebook clones for _toolkit/

require "fileutils"
require "json"
require "open3"
require "optparse"
require "pathname"
require "time"

# The subject is chosen by the wrapper that invoked this (see _toolkit/lib.sh):
# SUBJECT_DIR points at studio/lora/<subject>, and subject.env there names
# SUBJECT, MODEL and TRIGGER.
SUBJECT = ENV.fetch("SUBJECT") { abort "run a subject wrapper, not this script directly" }
MODEL = ENV.fetch("MODEL") { abort "run a subject wrapper, not this script directly" }
TRIGGER = ENV.fetch("TRIGGER", SUBJECT)
SUBJECT_DIR = Pathname.new(ENV.fetch("SUBJECT_DIR")).expand_path.freeze

DATASET_DIR = SUBJECT_DIR.join("dataset")
WEIGHTS_DIR = SUBJECT_DIR.join("weights", MODEL)
CACHE_DIR = SUBJECT_DIR.join(".cache", "kaggle")
LOG_PATH = WEIGHTS_DIR.join("kaggle_train.log")

IMAGE_EXT = %w[.jpg .jpeg .png .webp].freeze
# Kaggle's own ceiling for a GPU session. Asking for more is rejected at push.
MAX_TIMEOUT = 43_200
# Free tier. The CLI accepts NvidiaA100/NvidiaL4/NvidiaH100 too, but those are
# not what a free account is scheduled onto, and a T4 is the one the cuda_t4
# profile in render_config.rb is tuned for.
ACCELERATORS = %w[NvidiaTeslaT4 NvidiaTeslaT4Highmem NvidiaTeslaP100].freeze

options = {
  dry_run: false,
  async: false,
  steps: (ENV["LORA_KAGGLE_STEPS"] || "1800").to_i,
  sample_every: (ENV["LORA_KAGGLE_SAMPLE_EVERY"] || "500").to_i,
  accelerator: ENV.fetch("LORA_KAGGLE_ACCELERATOR", "NvidiaTeslaT4"),
  timeout: (ENV["LORA_KAGGLE_TIMEOUT"] || "32400").to_i,
  poll: (ENV["LORA_KAGGLE_POLL"] || "120").to_i,
  user: ENV["LORA_KAGGLE_USER"].to_s.strip,
  inline_token: false,
  # Whatever you labelled the secret in the notebook editor. It must hold a
  # Hugging Face token. Several may be listed; the notebook takes the first that
  # answers and prints which.
  secret: ENV.fetch("LORA_KAGGLE_SECRET", "HF_TOKEN").split(",").map(&:strip).reject(&:empty?),
  repo: ENV.fetch("PUB4_REPO", "https://github.com/anon987654321/pub4.git"),
  branch: ENV.fetch("PUB4_BRANCH", "main")
}

OptionParser.new do |parser|
  parser.banner = "Usage: run_train_kaggle.rb [options]"
  parser.on("--dry-run", "Write notebook and metadata, push nothing") { options[:dry_run] = true }
  parser.on("--async", "Push and exit without polling") { options[:async] = true }
  parser.on("--steps N", Integer, "Training steps (default #{options[:steps]})") { |v| options[:steps] = v }
  parser.on("--sample-every N", Integer, "Sample the prompt suite every N steps",
            "(default #{options[:sample_every]})") { |v| options[:sample_every] = v }
  parser.on("--accelerator NAME", "One of: #{ACCELERATORS.join(', ')}") { |v| options[:accelerator] = v }
  parser.on("--timeout SEC", Integer, "Kernel wall clock (max #{MAX_TIMEOUT})") { |v| options[:timeout] = v }
  parser.on("--user NAME", "Kaggle username") { |v| options[:user] = v }
  parser.on("--secret LABELS", "Kaggle secret(s) holding the HF token, comma-separated;",
            "first that answers wins (default #{options[:secret].join(',')})") do |value|
    options[:secret] = value.split(",").map(&:strip).reject(&:empty?)
  end
  parser.on("--inline-hf-token", "Write the local HF token into the notebook instead of",
            "reading a secret. Attaching a secret is browser-only, so this is",
            "the way to push without leaving the terminal. It puts the token in",
            "Kaggle's version history for this notebook — use a read-scoped one",
            "and revoke it afterwards.") { options[:inline_token] = true }
  parser.on("-h", "--help") { puts parser; exit 0 }
end.parse!

unless ACCELERATORS.include?(options[:accelerator])
  warn "warn: --accelerator #{options[:accelerator]} is not a free-tier accelerator"
  warn "fix: one of #{ACCELERATORS.join(', ')}"
end

if options[:timeout] > MAX_TIMEOUT
  abort "warn: --timeout #{options[:timeout]} exceeds Kaggle's #{MAX_TIMEOUT}s session cap"
end

def kaggle_available?
  _out, status = Open3.capture2e("kaggle", "--version")
  status.success?
rescue Errno::ENOENT
  false
end

# The username is not just for auth here — every id is owner-scoped, so we
# cannot name the notebook or the dataset without it.
#
# Three credential shapes exist and the CLI accepts all of them: the env pair,
# the legacy kaggle.json from Settings -> API -> Create New Token, and
# credentials.json written by the `kaggle auth login` OAuth flow. Only the last
# two carry a username, and which one is present depends on how you signed in.
CREDENTIAL_FILES = %w[~/.kaggle/credentials.json ~/.kaggle/kaggle.json].freeze

def resolve_user(explicit)
  return explicit unless explicit.empty?

  from_env = ENV["KAGGLE_USERNAME"].to_s.strip
  return from_env unless from_env.empty?

  CREDENTIAL_FILES.each do |candidate|
    path = Pathname.new(File.expand_path(candidate))
    next unless path.file?

    name = JSON.parse(path.read)["username"].to_s.strip
    return name unless name.empty?
  rescue StandardError
    next
  end

  ""
end

# Same places check_hf_flux_access.rb looks, so --check passing locally means
# there is a token here to inline.
HF_TOKEN_FILES = %w[~/.cache/huggingface/token ~/.huggingface/token].freeze

def local_hf_token
  %w[HF_TOKEN HUGGINGFACE_HUB_TOKEN].each do |key|
    value = ENV[key].to_s.strip
    return value unless value.empty?
  end

  HF_TOKEN_FILES.each do |candidate|
    path = Pathname.new(File.expand_path(candidate))
    next unless path.file?

    value = path.read.strip
    return value unless value.empty?
  end

  ""
end

def dataset_images(dir)
  dir.children.select { |path| path.file? && IMAGE_EXT.include?(path.extname.downcase) }.sort_by(&:to_s)
end

def local_checkpoints(dir)
  return [] unless dir.directory?

  dir.children.select { |path| path.file? && path.extname == ".safetensors" }.sort_by(&:to_s)
end

# ai-toolkit resumes from get_latest_save_path, which picks by os.path.getctime
# and not by the step in the filename. shutil.copy2 preserves mtime but not
# ctime, so every checkpoint restored into a fresh Kaggle session carries the
# same instant and "latest" decays to whatever order they were written in.
# Uploading only the newest removes the ambiguity — and the older ones are
# already on this disk, which is the only place they are wanted.
def newest_checkpoint(paths)
  return [] if paths.empty?

  [paths.max_by { |path| [path.basename.to_s[/\d+/].to_i, path.mtime] }]
end

def run(*command, chdir: nil)
  puts "run: #{command.join(' ')}"
  output, status = chdir ? Open3.capture2e(*command, chdir: chdir) : Open3.capture2e(*command)
  [output.to_s, status.success?]
end

# Dataset payload is flat on purpose. `kaggle datasets` defaults to --dir-mode
# skip, which silently drops subdirectories, and archives are unreliable because
# Kaggle expands some of them on upload and not others. Everything therefore
# goes in at the root and the notebook rebuilds the tree from an inventory it
# was generated with.
#
# The toolkit travels in the payload rather than being cloned, because a clone
# runs whatever is on the public remote — which is not what is on this disk, and
# on the first run of this lane was an entirely different directory layout. The
# job should run the code you are looking at.
def stage_dataset(images, checkpoints, toolkit, subject_files, dir)
  FileUtils.rm_rf(dir)
  FileUtils.mkdir_p(dir)
  images.each do |path|
    FileUtils.cp(path, dir.join(path.basename))
    caption = path.sub_ext(".txt")
    FileUtils.cp(caption, dir.join(caption.basename)) if caption.file?
  end
  (checkpoints + toolkit + subject_files).each { |path| FileUtils.cp(path, dir.join(path.basename)) }
  dir
end

def toolkit_files
  Pathname.new(__dir__).children.select { |path| path.file? && path.basename.to_s != "run_train_kaggle.rb" }
end

def subject_files
  %w[subject.env train.yaml lora].map { |name| SUBJECT_DIR.join(name) }.select(&:file?)
end

# Two ways in. Secrets are the right one — the token never enters the notebook,
# so it never enters Kaggle's version history — but attaching a secret to a
# notebook can only be done in the browser, and a notebook has to exist before
# it can be attached to. Inlining trades that away to make the push a single
# terminal command.
def token_block(options)
  unless options[:inline_token]
    return <<~PYTHON.strip
      # Kaggle Secrets are attached in the notebook editor and only readable
      # through their Python client. Labels are free text with no lookup by
      # value, so --secret takes candidates and this reports which answered.
      # It runs before any clone or download, so a miss fails in seconds.
      from kaggle_secrets import UserSecretsClient
      secrets = UserSecretsClient()
      token, used = None, None
      for label in #{options[:secret].inspect}:
          try:
              token, used = secrets.get_secret(label), label
              break
          except Exception:
              continue
      if not token:
          sys.exit("warn: no readable Kaggle secret among #{options[:secret].join(', ')}. "
                   "fix: Notebook editor -> Add-ons -> Secrets, and pass the label "
                   "you see there as --secret LABEL.")
      print(f"ok: secret {used}")
    PYTHON
  end

  <<~PYTHON.strip
    # Inlined by --inline-hf-token. This notebook is private, but the token is
    # in its source and therefore in every version Kaggle keeps of it. Revoke
    # it at huggingface.co/settings/tokens when the training is done.
    token = #{options[:hf_token].inspect}
    print("ok: inlined HF token")
  PYTHON
end

def notebook_source(options, dataset_slug)
  toolkit = "/kaggle/tmp/lora/_toolkit"
  subject_dir = "/kaggle/tmp/lora/#{SUBJECT}"
  <<~PYTHON
    # Generated by studio/lora/_toolkit/run_train_kaggle.rb — do not edit here.
    # Edits belong in the generator; this notebook is overwritten on every push.
    import os, pathlib, shutil, subprocess, sys

    # FLUX.1-dev is gated, so a Hugging Face token has to reach this box.
    #{token_block(options)}
    os.environ["HF_TOKEN"] = token
    os.environ["HUGGINGFACE_HUB_TOKEN"] = token

    # /kaggle/working is capped at 20 GB and persists; /kaggle/tmp is ~60 GB and
    # does not. The model cache is far too large for the former and is worth
    # nothing after the session, so it goes in the latter.
    os.environ["HF_HOME"] = "/kaggle/tmp/hf"
    os.environ["AI_TOOLKIT_ROOT"] = "/kaggle/tmp/ai-toolkit"
    pathlib.Path("/kaggle/tmp/hf").mkdir(parents=True, exist_ok=True)

    def sh(*command):
        subprocess.run(command, check=True)

    sh("apt-get", "-qq", "update")
    sh("apt-get", "-qq", "install", "-y", "ruby", "git")

    if not pathlib.Path("/kaggle/tmp/ai-toolkit/.git").exists():
        sh("git", "clone", "--depth", "1",
           "https://github.com/ostris/ai-toolkit.git", "/kaggle/tmp/ai-toolkit")
        # --system-site-packages so the image's torch is reused. A clean venv
        # would pull a second multi-GB torch off PyPI that is not matched to the
        # driver this box happens to have, and spend session time doing it.
        # run_ai_toolkit.rb requires a venv python, so it is still a venv.
        sh("python3", "-m", "venv", "--system-site-packages", "/kaggle/tmp/ai-toolkit/.venv")
        sh("/kaggle/tmp/ai-toolkit/.venv/bin/pip", "install", "-q", "--upgrade", "pip", "wheel")
        sh("/kaggle/tmp/ai-toolkit/.venv/bin/pip", "install", "-q", "-r",
           "/kaggle/tmp/ai-toolkit/requirements.txt")

    # The mounted dataset is flat, and the tree gets rebuilt from it here. The
    # inventory below was written when the payload was staged, so the split is
    # decided by the generator rather than guessed at from filenames: toolkit,
    # subject config, captioned training set, and any checkpoint to resume from.
    TOOLKIT = #{toolkit_files.map { |p| p.basename.to_s }.sort.inspect}
    SUBJECT_CONFIG = #{subject_files.map { |p| p.basename.to_s }.sort.inspect}

    mount = pathlib.Path("/kaggle/input/#{dataset_slug}")
    if not mount.exists():
        sys.exit(f"warn: dataset not mounted at {mount}")
    toolkit_dir = pathlib.Path("#{toolkit}")
    dataset = pathlib.Path("#{subject_dir}/dataset")
    weights = pathlib.Path("#{subject_dir}/weights/#{MODEL}")
    for directory in (toolkit_dir, dataset, weights):
        directory.mkdir(parents=True, exist_ok=True)

    counts = {"toolkit": 0, "config": 0, "data": 0, "checkpoint": 0}
    for item in sorted(mount.iterdir()):
        if item.name in TOOLKIT:
            target, key = toolkit_dir / item.name, "toolkit"
        elif item.name in SUBJECT_CONFIG:
            target, key = pathlib.Path("#{subject_dir}") / item.name, "config"
        elif item.suffix == ".safetensors":
            target, key = weights / item.name, "checkpoint"
        elif item.suffix.lower() in {".jpg", ".jpeg", ".png", ".webp", ".txt"}:
            target, key = dataset / item.name, "data"
        else:
            continue
        shutil.copy2(item, target)
        target.chmod(0o755)
        counts[key] += 1
    print("ok: " + ", ".join(f"{k} {v}" for k, v in counts.items()))
    if counts["toolkit"] != len(TOOLKIT):
        sys.exit(f"warn: expected {len(TOOLKIT)} toolkit files, mounted {counts['toolkit']}")

    env = dict(os.environ)
    env.update({
        # cuda_t4 is a render_config.rb profile, not an ai-toolkit device: fp16
        # because Turing has no bf16, quantised because 16 GB will not hold
        # FLUX.1-dev otherwise, 512 buckets because the budget is the clock.
        "LORA_DEVICE": "cuda_t4",
        "LORA_STEPS": "#{options[:steps]}",
        "LORA_SAMPLE_EVERY": "#{options[:sample_every]}",
        "LORA_SKIP_POSTPRO": "1",
    })
    # Invoked through sh so a clone that lost the mode bit still runs.
    subprocess.run(["sh", "#{subject_dir}/lora", "--train"], check=True, env=env,
                   cwd="#{toolkit}")

    # The adapter and the validation portraits leave the session; everything
    # else is reproducible. ai-toolkit samples the 12 curated prompts every 250
    # steps, so a training run is also the generate run — which is the whole
    # reason this lane does not need a paid one to see a face.
    out = pathlib.Path("/kaggle/working")
    kept = 0
    for weight in sorted(weights.glob("*.safetensors")):
        shutil.copy2(weight, out / weight.name)
        kept += 1
    samples = pathlib.Path("#{subject_dir}/out")
    shots = 0
    if samples.exists():
        for suffix in ("*.jpg", "*.jpeg", "*.png", "*.webp"):
            for sample in sorted(samples.glob(suffix)):
                shutil.copy2(sample, out / sample.name)
                shots += 1
    print(f"ok: wrote {kept} checkpoint(s) and {shots} sample(s) to /kaggle/working")
    if kept == 0:
        sys.exit("warn: training produced no .safetensors")
  PYTHON
end

def notebook_json(source)
  {
    "cells" => [{
      "cell_type" => "code",
      "execution_count" => nil,
      "metadata" => {},
      "outputs" => [],
      "source" => source.lines
    }],
    "metadata" => {
      "kernelspec" => { "display_name" => "Python 3", "language" => "python", "name" => "python3" },
      "language_info" => { "name" => "python" }
    },
    "nbformat" => 4,
    "nbformat_minor" => 5
  }
end

if options[:inline_token]
  options[:hf_token] = local_hf_token
  if options[:hf_token].empty?
    abort "warn: --inline-hf-token but no local Hugging Face token. " \
          "fix: hf auth login, or export HF_TOKEN=hf_..."
  end
end

user = resolve_user(options[:user])
if user.empty?
  abort "warn: no Kaggle username. fix: set KAGGLE_USERNAME and KAGGLE_KEY, or write ~/.kaggle/kaggle.json"
end

dataset_slug = "#{SUBJECT}-lora"
dataset_id = "#{user}/#{dataset_slug}"
kernel_slug = "#{SUBJECT}-flux-lora"
kernel_id = "#{user}/#{kernel_slug}"

images = dataset_images(DATASET_DIR)
abort "warn: no images in #{DATASET_DIR}" if images.empty?

checkpoints = newest_checkpoint(local_checkpoints(WEIGHTS_DIR))
puts "ok: subject #{SUBJECT} trigger #{TRIGGER} images #{images.length}"
checkpoints.each { |path| puts "ok: resuming from #{path.basename}" }
puts "ok: dataset #{dataset_id} kernel #{kernel_id}"
puts "ok: #{options[:accelerator]} steps=#{options[:steps]} timeout=#{options[:timeout]}s"

data_dir = stage_dataset(images, checkpoints, toolkit_files, subject_files, CACHE_DIR.join("data"))
File.write(data_dir.join("dataset-metadata.json"), JSON.pretty_generate({
  "title" => "#{SUBJECT} LoRA training set",
  "id" => dataset_id,
  "licenses" => [{ "name" => "other" }]
}))

push_dir = CACHE_DIR.join("kernel")
FileUtils.mkdir_p(push_dir)
File.write(push_dir.join("#{kernel_slug}.ipynb"),
           JSON.pretty_generate(notebook_json(notebook_source(options, dataset_slug))))
File.write(push_dir.join("kernel-metadata.json"), JSON.pretty_generate({
  "id" => kernel_id,
  "title" => "#{SUBJECT} FLUX LoRA",
  "code_file" => "#{kernel_slug}.ipynb",
  "language" => "python",
  "kernel_type" => "notebook",
  # Person LoRAs and the faces they are trained on stay private, both of them.
  "is_private" => "true",
  "enable_gpu" => "true",
  "enable_tpu" => "false",
  # Needed for the model download and the two git clones. Kaggle only grants it
  # to phone-verified accounts.
  "enable_internet" => "true",
  "dataset_sources" => [dataset_id],
  "competition_sources" => [],
  "kernel_sources" => [],
  "model_sources" => []
}))
puts "ok: staged #{push_dir}"

if options[:dry_run]
  puts "ok: dry-run — nothing pushed"
  puts "tip: review #{push_dir}/#{kernel_slug}.ipynb, then rerun without --dry-run"
  exit 0
end

abort "warn: kaggle CLI missing. fix: pipx install kaggle (or pip install kaggle)" unless kaggle_available?

# There is no upsert: create the first time, version every time after. `datasets
# status` is the only probe available and its behaviour on a dataset that does
# not exist is undocumented, so neither branch is trusted to be the right one —
# whichever runs first falls through to the other on the matching complaint.
def create_dataset(dir)
  run("kaggle", "datasets", "create", "-p", dir.to_s, "--dir-mode", "skip")
end

def version_dataset(dir, message)
  run("kaggle", "datasets", "version", "-p", dir.to_s, "-m", message, "--dir-mode", "skip")
end

probe, probe_ok = run("kaggle", "datasets", "status", dataset_id)
exists = probe_ok && !probe.to_s.downcase.match?(/not found|404|does not exist/)
message = "#{images.length} images, #{checkpoints.length} checkpoint(s)"

output, ok = exists ? version_dataset(data_dir, message) : create_dataset(data_dir)
unless ok
  text = output.to_s.downcase
  if exists && text.match?(/not found|404|does not exist/)
    output, ok = create_dataset(data_dir)
  elsif !exists && text.match?(/already (exists|in use)|duplicate/)
    output, ok = version_dataset(data_dir, message)
  end
end
abort "warn: dataset upload failed\n#{output}" unless ok
puts "ok: dataset #{dataset_id} uploaded"

output, ok = run("kaggle", "kernels", "push", "-p", push_dir.to_s,
                 "--accelerator", options[:accelerator], "-t", options[:timeout].to_s)
abort "warn: kernel push failed\n#{output}" unless ok
puts output.strip

FileUtils.mkdir_p(WEIGHTS_DIR)
sidecar = {
  pushed_at: Time.now.utc.iso8601,
  kernel: kernel_id,
  dataset: dataset_id,
  trigger_word: TRIGGER,
  steps: options[:steps],
  accelerator: options[:accelerator],
  timeout: options[:timeout],
  dataset_images: images.length,
  resumed_from: checkpoints.map { |path| path.basename.to_s }
}
File.write(WEIGHTS_DIR.join("kaggle_training.json"), JSON.pretty_generate(sidecar))

def append_log(lines)
  FileUtils.mkdir_p(LOG_PATH.dirname)
  File.open(LOG_PATH, "a") do |file|
    file.puts "--- #{Time.now.utc.iso8601}"
    lines.each { |line| file.puts line }
  end
end

if options[:async]
  append_log(["async push kernel=#{kernel_id} steps=#{options[:steps]}"])
  puts "ok: async — https://www.kaggle.com/code/#{kernel_id}"
  puts "tip: rerun without --async to poll, or pull manually:"
  puts "     kaggle kernels output #{kernel_id} -p #{WEIGHTS_DIR}"
  exit 0
end

# `kernels status` prints a free-text line rather than a code, so match on the
# words and treat anything unrecognised as still running — a wrong guess here
# costs one more poll, while a wrong "finished" loses the run.
deadline = Time.now + options[:timeout]
state = "running"
while Time.now < deadline
  output, _ok = run("kaggle", "kernels", "status", kernel_id)
  text = output.to_s.downcase
  case text
  when /complete/ then state = "complete"
  when /error|fail/ then state = "error"
  when /cancel/ then state = "cancelled"
  end
  puts "ok: status #{state}"
  break unless state == "running"

  sleep options[:poll]
end

if state != "complete"
  append_log(["kernel=#{kernel_id} state=#{state}"])
  warn "warn: kernel #{state}"
  warn "fix: logs at https://www.kaggle.com/code/#{kernel_id}"
  exit 1
end

output, ok = run("kaggle", "kernels", "output", kernel_id, "-p", WEIGHTS_DIR.to_s, "--force")
abort "warn: could not pull kernel output\n#{output}" unless ok

pulled = local_checkpoints(WEIGHTS_DIR).map { |path| path.basename.to_s } - checkpoints.map { |p| p.basename.to_s }
pulled.each { |name| puts "ok: weight #{WEIGHTS_DIR.join(name)}" }

# The output is one flat directory, so the validation portraits arrive in the
# weights dir. They are deliverables and belong with the rest of them.
out_dir = SUBJECT_DIR.join("out")
portraits = WEIGHTS_DIR.children.select { |path| path.file? && IMAGE_EXT.include?(path.extname.downcase) }
unless portraits.empty?
  out_dir.mkpath
  portraits.each { |path| FileUtils.mv(path.to_s, out_dir.join(path.basename).to_s) }
  puts "ok: #{portraits.length} sample portrait(s) in #{out_dir}"
end

append_log([
  "lora-train-kaggle: subject=#{SUBJECT} images=#{images.length} trigger=#{TRIGGER}",
  "kernel: #{kernel_id}",
  "dataset: #{dataset_id}",
  "steps: #{options[:steps]} accelerator: #{options[:accelerator]}",
  "resumed_from: #{checkpoints.map { |p| p.basename.to_s }.join(', ')}",
  "pulled: #{pulled.join(', ')}"
])

puts "ok: done weights_dir=#{WEIGHTS_DIR}"
if pulled.empty?
  warn "warn: kernel completed but no new .safetensors came back"
  warn "fix: check the notebook log at https://www.kaggle.com/code/#{kernel_id}"
  exit 3
end
puts "tip: ./lora --generate            # sample locally from the pulled checkpoint"
puts "tip: ./lora --train-kaggle        # again to resume; it re-uploads what it just pulled"
