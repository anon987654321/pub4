# 1️⃣ Clone the monorepo (or pull latest updates)
git clone https://github.com/yourname/awesome-llm-apps.git
cd awesome-llm-apps/advanced_llm_apps/resume_job_matcher

# 2️⃣ Install Ruby dependencies (production‑ready, isolated gems)
bundle install --deployment

# 3️⃣ Provide your OpenRouter API key
export OPENROUTER_API_KEY="sk_…"

# 4️⃣ Run the matcher against a résumé file and a job feed
bin/resume_job_matcher \
  --resume path/to/resume.pdf \
  --jobs   path/to/jobs.csv \
  --output matches.json
