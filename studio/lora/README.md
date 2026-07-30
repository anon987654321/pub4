# Ragnhild-portretter

Dette er ikke et filter lagt over et tilfeldig ansikt. Det er et forsøk på å gi deg tilbake deg selv i lys som er snillere — norsk, voksen, varm, ekte — slik at et bilde kan kjennes som et bedre minne, ikke en fremmed versjon av deg. Målet er et lite sett portretter som tåler nær blikk: ansiktet ditt først, stemning og magi etterpå, aldri omvendt.

FLUX.1-dev er valgt fordi den treffer et sjeldent punkt mellom fotorealisme og kontroll: en stor rectified-flow-transformer som forstår lys, hud, perspektiv og fotografisk språk bedre enn eldre diffusjonsmodeller, og som faktisk lytter til prompten i stedet for å levere generisk AI-glatthet. Den er åpen nok til at vi kan trene en personspesifikk LoRA oppå, sterk nok til at finjustering gir ekte likhet i stedet for bare stil, og presis nok til at vi kan variere location, objektiv og filmstock uten at ansiktet faller fra hverandre — det er derfor den slår raske generalist-generatorer når målet er ett navn, ett ansikt, mange verdener.

Teknisk sett starter vi med 17 kuraterte referansebilder av Ragnhild med tekstcaptions, trener en lav-rang LoRA-adapter (rank 32, triggerord `ragnhild`) oppå diffusjonsmodellen `black-forest-labs/FLUX.1-dev` via flow-matching og ai-toolkit på lokal MPS, slik at modellen lærer en personspesifikk representasjon i vektrommet i stedet for å gjette ansikt fra prompt alene; under trening caches latenter til disk, LoRA-vektene oppdateres over 1800 steg med AdamW 8-bit og EMA, validering skjer med 12 faste fotografiske prompts fra `prompts.yaml`, og hele kjeden styres av Ruby (`check_hf_flux_access.rb`, `render_config.rb`, `postpro_samples.rb`) via `run_generate.sh` — kun ai-toolkit sin `run.py` er Python-grensen — før eventuell `portrait`-postpro. Det skiller seg fra generiske bildegeneratorer som Grok Imagine, GPT-image eller Google Imagen fordi de er generalistiske tekst-til-bilde-modeller uten persistent, personbundet finjustering: de kan lage plausible portretter fra beskrivelse, men holder sjelden stabil identitet på tvers av lys, vinkel, antrekk og stil, og de kan ikke trenes på godkjente kildebilder med en eksplisitt likeness-sløyfe. Her eies hele kjeden lokalt, kan reproduseres og forbedres iterativt, og skiller bevisst mellom kildebaserte portretter, prompt-only forhåndsvisning og ekte LoRA-generering.

Alle ferdige bilder ligger flatt i denne mappen. Det eneste versjonerte treningsdatasettet er den caption-bærende mappen `training/ragnhild/ai_toolkit/dataset/`; uttrukne videoframes, latent-cache, råkopier og ZIP-bunter regenereres lokalt og versjoneres ikke. Originalvideoer ligger i `training/ragnhild/sources/`, trening og skript i `training/ragnhild/ai_toolkit/`, og ferdige vekter/eksporter i `ragnhild/`. Start med `./run_generate.sh --check` eller `--train`. Prompt-only HF-forhåndsvisninger ble forkastet fordi de ikke ga identitetslikhet. Spørsmålet er alltid det samme: er det Ragnhild?

## Dual-track train (RunPod / local *or* Replicate)

Same dataset and trigger (`ragnhild`); pick the lane that fits ops cost.

| Lane | Command | When |
|------|---------|------|
| **Local / RunPod** | `training/ragnhild/ai_toolkit/run_generate.sh --train` | Full ai-toolkit control (rank 32, 1800 steps, multi-res YAML) |
| **Replicate API** | `training/ragnhild/ai_toolkit/run_generate.sh --train-replicate` | No SSH/tmux; ~1000 steps on hosted H100s; private destination model |

Replicate path (`run_train_replicate.rb`):

1. Zips `dataset/` → `exports/ragnhild_dataset.zip`
2. Uploads via Replicate Files API
3. Trains `ostris/flux-dev-lora-trainer` → destination `$user/ragnhild-flux` (override with `LORA_REPLICATE_DEST`)
4. Polls until done (or `--async` + `REPLICATE_WEBHOOK_URL`)
5. Pulls `output.weights` into `weights/ragnhild_v2/` when downloadable

Requires `REPLICATE_API_TOKEN`. Dry-run: `./run_train_replicate.sh --dry-run`. Keep the private model private; do not publish person LoRAs publicly.

## Toolkit layout

The scripts live once, in `_toolkit/`, and every subject shares them. A subject
directory holds only what is genuinely its own — `dataset/`, `sources/`,
`prompts.yaml`, `train_<subject>.yaml`, `weights/` — plus a `subject.env` naming
the three things that differ:

```sh
SUBJECT=johann
MODEL=johann_v1
TRIGGER=johann
```

The commands are unchanged: `training/<subject>/ai_toolkit/run_generate.sh` and
friends are thin wrappers that export `SUBJECT_DIR` and hand over to `_toolkit/`.
Run a `_toolkit/` script directly and it refuses, because it cannot know which
subject you meant.

This replaced a per-subject fork. `johann/ai_toolkit` was a byte-for-byte copy of
`ragnhild/ai_toolkit` apart from the name, so the four path fixes the `studio/`
move needed had to be made twice, with nothing to catch a missed copy.

Environment knobs are `LORA_*` for every subject (`LORA_DEVICE`, `LORA_LR`,
`LORA_PROMPT`, `LORA_FLUX_MODEL`, `LORA_REPLICATE_DEST`, …). They used to be
`RAGNHILD_*` and `JOHANN_*`: a knob named after the subject is not a knob, since
the subject is already chosen by which directory you are in.

## Status

- **ragnhild**: dataset complete (17 captioned images), full pipeline in `training/ragnhild/ai_toolkit/`. `weights/ragnhild_v2/` has no `.safetensors` yet — local MPS training died in the Metal compiler, and the last run failed on the gated FLUX.1-dev repo (needs `HF_TOKEN` with accepted license). An earlier Replicate run trained `basicfeatures/ragnhild:6197a9e1…` (see `ragnhild/weights/replicate_train.log`); with `REPLICATE_API_TOKEN` set, either pull those weights or re-run `--train-replicate`.
- **johann**: pipeline scaffolded in `training/johann/ai_toolkit/` (trigger `johann`, model `johann_v1`, same dual-track scripts). Dataset holds 3 captioned images (night selfie, indoor cap selfie, dusk park selfie — the latter two face-cropped from `training/johann/sources/`) — still too few to train. Curate up to 12-18 varied photos (angles, light, expressions) into `training/johann/sources/`, caption them into `training/johann/ai_toolkit/dataset/`, then `./run_generate.sh --train` or `--train-replicate`.

## Johann

Samme kjede som Ragnhild: FLUX.1-dev + ai-toolkit LoRA (rank 32, triggerord `johann`), dual-track lokal/RunPod eller Replicate. Kildebilder i `johann/`, trening i `training/johann/ai_toolkit/`, ferdige vekter i `training/johann/ai_toolkit/weights/johann_v1/`. Spørsmålet er det samme: er det Johann?
