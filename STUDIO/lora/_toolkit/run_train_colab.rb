#!/usr/bin/env ruby
# frozen_string_literal: true

# Fourth train lane: Google Colab. Free 16 GB T4, no phone verification.
#
# Unlike the Kaggle lane there is no API to push to and no way to drive this
# headlessly — Colab is a browser. What there is, is a GitHub loader: a notebook
# committed to a public repo opens in Colab from a URL. So this writes the
# notebook into the subject directory, and you commit it and click the link.
#
# The notebook clones this repo for the toolkit and the captioned dataset, which
# is the right dependency here for the reason it was the wrong one on Kaggle:
# Colab has no dataset mount to carry a payload in, and the repo is public.
#
# Usage:
#   ./lora --train-colab            # write the notebook, print the URL
#   ./lora --train-colab --steps 900
#
# Env:
#   LORA_COLAB_STEPS        default 1800
#   LORA_COLAB_SAMPLE_EVERY default 500
#   PUB4_REPO / PUB4_BRANCH the checkout the notebook clones

require "json"
require "optparse"
require "pathname"

SUBJECT = ENV.fetch("SUBJECT") { abort "run a subject wrapper, not this script directly" }
SUBJECT_DIR = Pathname.new(ENV.fetch("SUBJECT_DIR")).expand_path.freeze
NOTEBOOK = SUBJECT_DIR.join("colab.ipynb")

options = {
  steps: (ENV["LORA_COLAB_STEPS"] || "1800").to_i,
  sample_every: (ENV["LORA_COLAB_SAMPLE_EVERY"] || "500").to_i,
  repo: ENV.fetch("PUB4_REPO", "https://github.com/anon987654321/pub4.git"),
  branch: ENV.fetch("PUB4_BRANCH", "main"),
  drive: true,
}

OptionParser.new do |parser|
  parser.banner = "Usage: run_train_colab.rb [options]"
  parser.on("--steps N", Integer, "Training steps (default #{options[:steps]})") { |v| options[:steps] = v }
  parser.on("--sample-every N", Integer, "Sample every N steps") { |v| options[:sample_every] = v }
  parser.on("--no-drive", "Do not mount Drive (nothing survives the runtime)") { options[:drive] = false }
  parser.on("-h", "--help") { puts parser; exit 0 }
end.parse!

def github_slug(repo)
  repo[%r{github\.com[:/]+([^/]+/[^/]+?)(?:\.git)?\z}, 1]
end

# Drive is what makes a second session cheaper than a first: a free runtime is
# capped around 12 h with an idle disconnect well before that, and keeps nothing.
def drive_cell(options)
  return <<~PYTHON.strip unless options[:drive]
    # --no-drive: checkpoints live in /content and die with the runtime.
    import os
    os.environ["LORA_PERSIST_DIR"] = "/content/persist"
  PYTHON

  <<~PYTHON.strip
    # Checkpoints and portraits go to Drive so a disconnect costs the session
    # and not the training. Re-running the notebook resumes from the newest.
    import os
    from google.colab import drive
    drive.mount("/content/drive")
    os.environ["LORA_PERSIST_DIR"] = "/content/drive/MyDrive/lora/#{SUBJECT}"
    os.makedirs(os.environ["LORA_PERSIST_DIR"], exist_ok=True)
  PYTHON
end

# Colab has a secrets store in the left sidebar (key icon). Falls back to a
# prompt so a first run is not blocked on finding it.
def token_cell
  <<~PYTHON.strip
    import os
    try:
        from google.colab import userdata
        os.environ["HF_TOKEN"] = userdata.get("HF_TOKEN")
        print("ok: HF_TOKEN from Colab secrets")
    except Exception:
        import getpass
        os.environ["HF_TOKEN"] = getpass.getpass("HF token (read scope, FLUX.1-dev licence accepted): ")
    assert os.environ.get("HF_TOKEN"), "no HF token"
  PYTHON
end

def setup_cell(options)
  <<~PYTHON.strip
    import subprocess
    subprocess.run("apt-get -qq update && apt-get -qq install -y ruby git",
                   shell=True, check=True)
    if not os.path.isdir("/content/pub4/.git"):
        subprocess.run(["git", "clone", "--branch", "#{options[:branch]}", "--depth", "1",
                        "#{options[:repo]}", "/content/pub4"], check=True)
    else:
        subprocess.run(["git", "-C", "/content/pub4", "pull", "--ff-only"], check=True)
    # Runtime type is a menu item nobody remembers, and a CPU runtime does not
    # announce itself — it trains at a rate that never finishes. On Kaggle
    # the equivalent oversight cost an hour before anything said why, so this
    # asserts rather than prints.
    gpu = subprocess.run(["nvidia-smi", "--query-gpu=name,memory.total", "--format=csv,noheader"],
                         capture_output=True, text=True)
    if gpu.returncode != 0 or not gpu.stdout.strip():
        raise SystemExit("warn: no GPU on this runtime, so training would never finish. "
                         "fix: Runtime -> Change runtime type -> T4 GPU, then Run all again.")
    print("ok: GPU", gpu.stdout.strip())
  PYTHON
end

# Where the training images come from, and why it is not the clone.
#
# The clone is what makes this lane need no token, and it is also the reason to
# think before using it: PUB4_REPO defaults to the public pub4 origin, so
# "clone the repo for the dataset" means "publish the photographs first". For
# generated subjects that is fine. For photographs of a person it is a decision
# nobody should make by running a notebook.
#
# Drive is already mounted a few cells above, for checkpoints. The same mount
# carries a dataset, so the images reach the GPU without reaching GitHub: put
# them in MyDrive/lora/<subject>/dataset and this prefers them over anything in
# the checkout.
#
# It fails rather than falling through when neither source has images. A lane
# that trains on an empty directory produces a LoRA of nothing after several
# hours, and the failure would surface as a bad likeness rather than as a
# missing dataset.
def dataset_cell(options)
  drive_note = options[:drive] ? "" : " (--no-drive: Drive was not mounted, so only the checkout is checked)"
  <<~PYTHON.strip
    import glob, os, shutil
    # Where the toolkit expects to find them, whichever source wins.
    target = "/content/pub4/STUDIO/lora/#{SUBJECT}/dataset"
    drive_set = "/content/drive/MyDrive/lora/#{SUBJECT}/dataset"

    def count(path):
        return len(glob.glob(os.path.join(path, "*.jpg")) +
                   glob.glob(os.path.join(path, "*.jpeg")) +
                   glob.glob(os.path.join(path, "*.png")) +
                   glob.glob(os.path.join(path, "*.webp")))

    if count(drive_set):
        os.makedirs(os.path.dirname(target), exist_ok=True)
        if os.path.islink(target) or os.path.isfile(target):
            os.remove(target)
        elif os.path.isdir(target):
            shutil.rmtree(target)
        shutil.copytree(drive_set, target)
        print("ok: dataset from Drive —", count(target), "images (not from the public repo)")
    elif count(target):
        print("ok: dataset from the checkout —", count(target), "images")
        print("note: these images are public, because #{options[:repo]} is.")
    else:
        raise SystemExit(
            "warn: no training images.#{drive_note}\\n"
            "fix: upload the captioned dataset to Drive at MyDrive/lora/#{SUBJECT}/dataset "
            "(images plus their .txt captions), then Run all again."
        )

    # Every image needs its caption. ai-toolkit resolves <stem>.txt and falls
    # through to the empty string when it is absent, so a broken pair is not an
    # error there — it is an uncaptioned training image, and the run reports
    # nothing.
    stems = {os.path.splitext(os.path.basename(p))[0]
             for p in glob.glob(os.path.join(target, "*"))
             if not p.endswith(".txt")}
    captions = {os.path.splitext(os.path.basename(p))[0]
                for p in glob.glob(os.path.join(target, "*.txt"))}
    missing = sorted(stems - captions)
    if missing:
        raise SystemExit("warn: %d image(s) have no .txt caption: %s\\n"
                         "fix: upload the captions alongside the images."
                         % (len(missing), ", ".join(missing[:6])))
    print("ok: every image is captioned")
  PYTHON
end

def train_cell(options)
  <<~PYTHON.strip
    # Everything past here is Ruby. cuda_t4 is a render_config.rb profile:
    # fp16 because Turing has no bf16, quantised because 16 GB will not hold
    # FLUX.1-dev otherwise, 512 buckets because the budget is the clock.
    os.environ["LORA_STEPS"] = "#{options[:steps]}"
    os.environ["LORA_SAMPLE_EVERY"] = "#{options[:sample_every]}"

    # Piped and re-printed, NOT subprocess.run(check=True).
    #
    # A notebook does not show you a child process's output. IPython captures
    # writes to Python's sys.stdout; a subprocess inherits the kernel's file
    # descriptor 1 and writes past it, into a kernel log the browser never
    # renders. So the whole Ruby session — every ok:, every run:, every warn:,
    # and whatever pip said before it failed — went somewhere unreadable, and
    # the only thing that reached the page was CalledProcessError naming
    # subprocess.py. A run failed this way with literally no diagnostic
    # attached: not the error, not even the first "ok:" line.
    #
    # Streamed line by line rather than captured at the end, because this runs
    # for hours. capture_output=True would buffer the lot and show it after the
    # fact, so a live run would look identical to a hung one.
    proc = subprocess.Popen(
        ["ruby", "/content/pub4/STUDIO/lora/_toolkit/colab_session.rb", "#{SUBJECT}"],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
    tail = []
    for line in proc.stdout:
        print(line, end="")
        tail.append(line)
        del tail[:-40]
    proc.wait()
    if proc.returncode:
        raise SystemExit(
            "training failed (exit %d). The cause is in the output above; the last "
            "40 lines are:\\n%s" % (proc.returncode, "".join(tail)))
  PYTHON
end

def markdown(options)
  slug = github_slug(options[:repo])
  <<~MARKDOWN
    # #{SUBJECT} — FLUX LoRA

    Generated by `STUDIO/lora/_toolkit/run_train_colab.rb`. Edits belong in the
    generator; this file is overwritten.

    **Runtime → Change runtime type → T4 GPU** before running, or it trains on a
    CPU and never finishes.

    Set `HF_TOKEN` in the sidebar (🔑) to a Hugging Face token that has accepted
    the [FLUX.1-dev licence](https://huggingface.co/black-forest-labs/FLUX.1-dev).

    #{options[:steps]} steps, sampling twelve lighting setups every
    #{options[:sample_every]}. A free session is capped near 12 h and disconnects
    when idle, so this is likely more than one sitting — checkpoints go to Drive
    and re-running resumes from the newest. Source: `#{slug}`.
  MARKDOWN
end

def cell(type, source)
  base = { "cell_type" => type, "metadata" => {}, "source" => source.lines }
  type == "code" ? base.merge("execution_count" => nil, "outputs" => []) : base
end

notebook = {
  "cells" => [
    cell("markdown", markdown(options)),
    cell("code", token_cell),
    cell("code", drive_cell(options)),
    cell("code", setup_cell(options)),
    # After the clone, because it may overwrite what the clone brought, and
    # before training, because it is the last point where a missing dataset is
    # cheap to discover.
    cell("code", dataset_cell(options)),
    cell("code", train_cell(options)),
  ],
  "metadata" => {
    "accelerator" => "GPU",
    "colab" => { "provenance" => [], "gpuType" => "T4" },
    "kernelspec" => { "display_name" => "Python 3", "name" => "python3" },
    "language_info" => { "name" => "python" },
  },
  "nbformat" => 4,
  "nbformat_minor" => 0
}

NOTEBOOK.write("#{JSON.pretty_generate(notebook)}\n")
puts "ok: wrote #{NOTEBOOK}"
puts "ok: #{options[:steps]} steps, sample every #{options[:sample_every]}, drive #{options[:drive]}"
puts
puts "next: commit and push it, then open"
puts "  https://colab.research.google.com/github/#{github_slug(options[:repo])}/blob/#{options[:branch]}/STUDIO/lora/#{SUBJECT}/colab.ipynb"
puts
puts "then: Runtime -> Change runtime type -> T4 GPU, set HF_TOKEN in the sidebar key icon, Run all"
