# 1️⃣ Clone the repository (shallow copy for speed)
git clone --depth 1 https://github.com/your-org/awesome-llm-apps.git
cd awesome-llm-apps/advanced_llm_apps/llm_finetuning_tutorials/gemma3_finetuning

# 2️⃣ Install Ruby dependencies (quiet mode suppresses Bundler output)
bundle install --quiet

# 3️⃣ Download the base Gemma 3 checkpoint (cached on first run)
bin/gemmasetup download

# 4️⃣ Launch the fine‑tuning pipeline
#    Default: 3 epochs, 8 GB VRAM, output stored in `output/`
bin/gemmasetup finetune
