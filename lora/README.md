# Ragnhild-portretter

Denne mappen inneholder Ragnhild-fotoprosjektet. Målet er enkelt: **hun skal se ut som seg selv** — varm, naturlig, norsk, i 40-årene, med ekte hudtekstur og mildt lys. Ikke en generisk modell. Ikke et ansiktsbytte.

---

## Hvor bildene ligger

Alle ferdige bilder ligger **flatt i denne mappen** (`pub4/lora/`). Åpne den i Finder. Du trenger ikke lete i undermapper.

| Filer | Hva de er |
|-------|-----------|
| `ragnhild_final_*.jpg` | **Beste materiale nå.** Ekte bilder av Ragnhild, lett beskåret og fargegradert. |
| `ragnhild_final_contact.jpg` | Ett ark med alle 16 finalbilder for rask gjennomgang. |
| `ragnhild_hf_*.jpg` | Tidlige AI-tester. **Ikke godkjent** som Ragnhild. |
| `ragnhild_hf_*_portrait.jpg` | Samme tester, med lett portrettpolering. |

Treningsfiler og skript ligger under `training/ragnhild/`. Du kan ignorere det med mindre du kjører pipelinen selv.

---

## Tre typer bilder — ikke bland dem

**1. Kildeportretter (`ragnhild_final_*`)**  
Disse starter fra ekte rammer av Ragnhild. Ligner de henne, er det fordi de begynte som henne. **Bruk disse til profil inntil LoRA-resultater er godkjent.**

**2. HF-forhåndsvisning (`ragnhild_hf_*`)**  
Laget med Hugging Faces raske FLUX-modell og bare tekst. Ingen egen «Ragnhild-hjerne» er koblet på. Behandle dem som stemningstester, ikke ferdige portretter.

**3. LoRA-portretter (kommer)**  
Maskinen lærer Ragnhild av 17 treningsbilder og lager nye scener. Hvert bilde må sjekkes med øyet før vi beholder det. **Trening pågår nå** (se under).

---

## Status

| Steg | Tilstand |
|------|----------|
| Kildeportrettsett (16) | Ferdig |
| HF-forhåndsvisning (12) | Ferdig — ikke identitetsgodkjent |
| Hugging Face FLUX-lisens | **Godkjent** |
| LoRA-trening (`ragnhild_v2`) | **Pågår** — laster ned FLUX, deretter ~1800 treningssteg |
| Nytt LoRA-portrettsett | Venter på trening + manuell vurdering |

**Rekkefølge:** likhet først, skjønnhet etterpå, effekter til slutt.

---

## Hva treningen gjør

1. Laster ned **FLUX.1-dev** — en bildekvalitetsmodell fra Hugging Face (~24 GB).
2. Studerer 17 utvalgte bilder i `training/ragnhild/ai_toolkit/dataset/`.
3. Bygger en liten tilleggsfil (en **LoRA**) som lærer modellen «dette er Ragnhild».
4. Genererer prøveportretter ved steg 250, 500, 750, … opp til 1800.
5. Kopierer nye prøver hit og legger på lett `portrait`-grading.

Trening tar timer på Mac (Apple Silicon). Følg med slik:

```sh
tail -f training/ragnhild/ai_toolkit/train_run.log
```

Når den er ferdig, se etter nye `ragnhild_hf_*.jpg` eller LoRA-prøver i `lora/`.

---

## Slik vurderer du et godt portrett

Still ett spørsmål: **«Er det Ragnhild?»**

Sjekk ansiktsform, øyne, munn, alder og uttrykk før du bryr deg om filmlook eller bakgrunn.

- **Naturlig profilenergi:** smileportrettene i de høyere `ragnhild_final_*`-numrene
- **Identitetssjekk:** rolige nærportrett og svart-hvitt `mono`
- **Analog varme:** `portra_warm`, `nordic_open_shade`, `hardanger_gold`

Forkast alt som føles for ungt, for glatt eller som en annen kvinne. Vi har allerede kastet ett tidlig testbilde av den grunn.

Vi sikter mot **analog portrettfilm**, ikke plastglamour: mykt nordisk lys, dempet farge, fint korn, moden hud beholdt.

---

## For deg som kjører pipelinen

Du trenger [ai-toolkit](https://github.com/ostris/ai-toolkit) på `/Users/mac/ai-toolkit`, et Hugging Face-token, og **Agree** klikket på [FLUX.1-dev](https://huggingface.co/black-forest-labs/FLUX.1-dev) for samme konto som tokenet.

```sh
cd training/ragnhild/ai_toolkit

./run_generate.sh --check      # sjekk tilgang og datasett
./run_generate.sh --train        # tren LoRA, synk prøver til lora/
./run_generate.sh --generate     # nye bilder fra trenede vekter
./run_generate.sh --postpro      # portrettgrading på ragnhild_hf_* bare
```

Konfigurasjon: `train_ragnhild.yaml`, `generate_ragnhild.yaml`.  
Tilgangssjekk: `check_hf_flux_access.py`.

**Innlogging er ikke det samme som lisens.** Tokenet bekrefter hvem du er. **Agree**-knappen på nettsiden gir nedlastingstilgang. Du trenger begge.

---

## Mappeoversikt

```
lora/                         ← alle leveransebilder her
training/ragnhild/
  ai_toolkit/dataset/         ← treningsbilder
  ai_toolkit/weights/         ← LoRA-vekter (ikke bilder)
  ai_toolkit/run_generate.sh  ← start her
```

---

## Det vi unngår

- Beauty-filtre og ungdomsutglatting
- Å binde utseendet hennes til én caps eller ett antrekk
- Å beholde hvert AI-utkast — de fleste slettes
- Å kalle prompt-bilder «ferdige Ragnhild-portretter»

---

## Neste steg etter trening

1. Åpne nye prøver i `lora/`.
2. Behold bare bilder som leses som Ragnhild.
3. Kjør `./run_generate.sh --generate` for et fullt sett med 12 prompts.
4. Legg portrett-postpro bare på godkjente bilder.

Magien kan få glitre litt. Den får ikke lyve.