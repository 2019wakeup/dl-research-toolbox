# Current Practices 2026

Use these notes as background when answering or implementing large dataset download workflows.

- Hugging Face current docs say `huggingface_hub` can dry-run downloads and that faster downloads now use `hf_xet`; `hf_transfer` is deprecated for current LFS-era guidance.
- aria2 1.37.0 supports resume through control files, segmented HTTP/FTP downloads, proxy options, and input files. Keep `.aria2` files until recovery is complete.
- curl and Wget both honor proxy environment variables; curl treats lowercase `http_proxy` specially, while `HTTPS_PROXY`, `ALL_PROXY`, and `NO_PROXY` are still useful.
- conda supports `proxy_servers`, but normally reads `HTTP_PROXY` and `HTTPS_PROXY`; prefer correct proxy schemes and trusted CA configuration instead of disabling SSL.
- OpenXLab supports dataset `get` for whole repositories and `download` for individual files through CLI and SDK.
- ModelScope commonly exposes datasets through `modelscope download`, `MsDataset.load`, or Git LFS.
- DVC `pull` downloads tracked files from configured remotes and supports target-specific pulls and parallel jobs.
- DataLad can download from URLs with credential management and optional hashing.
- rclone is useful for cloud/object-store movement and normally verifies checksums; avoid `--ignore-checksum` except when deliberately accepting corruption risk.

Mirror trust rules:

1. Exact mirror: official file hashes or Git LFS OIDs must match.
2. Subset mirror: every mirrored file must match the corresponding official file, and missing files must be listed.
3. Superset mirror: official files must match, extra files must be separately documented.
4. Repacked mirror: compare sample-level IDs/content hashes, schema, split sizes, and statistics; do not call it official-equivalent unless coverage is demonstrated.
