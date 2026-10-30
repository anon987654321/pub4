# Lovdata source use

MASTER's Lovdata adapter is deliberately narrow. It discovers official individual
law/regulation references and can retrieve one official document page. It is not a
crawler, bulk downloader, local legal corpus, cache or retrieval-augmented-generation
index.

## Source and terms

Official Lovdata API/data information: https://lovdata.no/info/api

Current Lovdata service terms (last changed 31 October 2025):
https://lovdata.no/artikkel/brukervilkar_for_lovdatas_tjenester/1319

Norwegian Licence for Open Government Data 2.0:
https://data.norge.no/nlod/no/2.0

The terms distinguish ordinary open-service content from an exception for individual
current formal laws and central regulations when Lovdata is credited and NLOD 2.0 is
followed. Mass downloading and systematic extraction are not permitted through the
ordinary open services. The terms also restrict AI use: only eligible individual
documents originally prepared by public bodies may be used, and only where the AI
program does not store the content or use it for model training. Do not use the
adapter to build a corpus, embeddings, RAG index, fine-tuning set or training data.

## Runtime behaviour

- action=search returns official Lovdata document links and search snippets only.
- action=lookup may retrieve one single public law/regulation page.
- LOV-YYYY-MM-DD-N and FOR-YYYY-MM-DD-N are accepted as direct document identifiers.
- The optional section selects one provision, for example 15-7.
- Only HTTPS URLs on the exact lovdata.no host and approved law/regulation document
  paths are accepted. Lookalike domains, general site pages and arbitrary URLs are refused.
- The adapter does not write document text to disk or cache it. It uses the existing
  guarded WebSearch/WebFetch transports, including SSRF checks and untrusted-output
  screening.

## Explicit opt-in for AI text retrieval

Search/link discovery works by default. Reading document text is disabled until the
operator sets:

    MASTER_LOVDATA_AI_USE=single-document-no-storage-no-training

Set this only after checking the actual provider, logging, conversation-retention and
training settings for the runtime that will receive the text. This variable is an
operator acknowledgement, not a technical attestation: it cannot disable retention
inside an external model provider, this chat client, shell history or other surrounding
systems. If those conditions cannot be established, leave the variable unset and use
the returned official links for human reading instead.

Legal text is source material, not legal advice. Verify the current official text,
effective date, transitional rules and amendments before relying on it.
