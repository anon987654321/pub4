# Provider catalog

`Providers::CatalogIndex` (`catalog_index.rb`) indexes external model catalogs into
`~/.master/provider_catalog.sqlite3`.

## Add a source

1. Add an entry to `SOURCES` with `url`, `kind`, and `normalizer`.
2. Implement `normalize_<name>` (or reuse an existing normalizer) on the class.
3. Refresh via `MASTER/bin/provider-catalog` or `CatalogIndex#refresh`.

## Built-in sources

| Key | Kind | Normalizer |
|-----|------|------------|
| `openrouter` | llm_router | `openrouter` |
| `replicate` | model_marketplace | `replicate` |
| `replicate_github` | github_model_index | `replicate` (URL from `REPLICATE_MODELS_INDEX_URL`) |

File imports use `import_file(source_name, path, normalizer: ...)`.
