# Repligen

Repligen is MASTER's noninteractive Replicate boundary. It generates images, downloads a result when an output path is requested, searches the provider catalog, synchronizes a bounded local catalog, and reports catalog statistics. It never installs gems, scrapes the website, or stores credentials in the repository.

MASTER normally chooses it from natural language, so users do not need these commands. The CLI remains useful for diagnostics:

```sh
ruby MASTER/tools/repligen.rb generate --prompt "Bergen rain, 35mm documentary photograph" --output .master/media/bergen.webp
ruby MASTER/tools/repligen.rb search flux --limit 100
ruby MASTER/tools/repligen.rb sync --limit 250
ruby MASTER/tools/repligen.rb stats
ruby MASTER/tools/repligen.rb capabilities
```

Credentials resolve from `REPLICATE_API_TOKEN`, `REPLICATE_API_KEY`, or `~/.config/repligen/config.json`. Catalog state defaults to `~/.cache/repligen/models.json`. MASTER routes explicit image-generation requests through this boundary; it does not claim a separate local identity-model path.

Generation returns provider URLs unless `--output FILE` is supplied. Missing credentials, missing outputs, provider failures, cancellation, and timeouts are explicit failures; the tool does not silently substitute a model or claim a local file exists.

The `capabilities` command emits the executable 60-item Repligen/LoRA contract as JSON. Generated assets use deterministic batch variation, model-specific input schemas, content-addressed caching, checksums, provenance sidecars, gallery manifests, and optional Postpro handoff.
