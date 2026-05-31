# tools

Maintainer-only utilities. **Not** mirrored to the public `ovip` repo.

| File | Purpose |
|---|---|
| [`bundle_for_eda.py`](bundle_for_eda.py) | Chunks the VIP into ≤100 KB files for upload to EDA Playground. Run with `python3 tools/bundle_for_eda.py --out eda_bundle/`. |
| [`eda_tb.sv`](eda_tb.sv) | Top-level stub used by the EDA Playground build (paired with the bundle output). |
| [`sync_to_public.sh`](sync_to_public.sh) | Mirrors the publishable subset of this repo to the public `ovip` GitHub repo. The allowlist at the top of the script is the source of truth for what's "public". |
| [`WRAP_IMPLEMENTATION.md`](WRAP_IMPLEMENTATION.md) | Design notes for the deferred AXI WRAP burst implementation. Working document for whoever picks up that feature. |
