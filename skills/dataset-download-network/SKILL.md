---
name: dataset-download-network
description: Use when planning, diagnosing, or executing large dataset downloads in China-facing research environments, including Hugging Face, ModelScope, OpenDataLab/OpenXLab, Kaggle, Git LFS, DVC, DataLad, rclone, HTTP mirrors, proxy configuration, resumable transfers, and mirror integrity validation.
metadata:
  short-description: Robust dataset downloads in China networks
---

# Dataset Download Network

Use this skill when a user needs reliable large dataset downloads, proxy/network diagnosis, mirror validation, or a reusable engineering workflow for research data acquisition.

## Operating Rules

1. Prefer current official CLI/SDK paths before generic downloaders:
   - Hugging Face: `hf download` or `huggingface_hub.snapshot_download`; modern flows should account for `hf_xet`.
   - ModelScope: `modelscope download` or `MsDataset.load`.
   - OpenDataLab/OpenXLab: `openxlab dataset get/download`.
   - DVC/DataLad/rclone: use when the project already exposes data through those systems.
2. Treat mirrors as untrusted until verified. Exact official hashes win. If hashes are unavailable, require manifest, size, sample hash, schema, and distribution checks. A mirror that is only a subset/superset must be documented as such.
3. Diagnose network before changing tools:
   - compare proxy path vs direct path;
   - inspect `http_proxy`, `https_proxy`, `ALL_PROXY`, `NO_PROXY` without printing secrets;
   - test DNS, TLS, redirects, and signed URL expiry separately.
4. Avoid destructive cleanup. Preserve partial files, cache folders, `.aria2` control files, DVC cache, HF cache, and Git LFS metadata until recovery is complete.
5. Do not recommend disabling TLS verification except as a last-resort diagnostic in a controlled institutional proxy environment; prefer installing the institution CA or using system trust stores.

## Workflow

1. Identify the source type: HF, ModelScope, OpenXLab, Kaggle, Git LFS, raw HTTP, object storage, DVC/DataLad, or cloud drive.
2. Run the local probe:

```bash
python3 skills/dataset-download-network/scripts/dataset_download_probe.py probe
python3 skills/dataset-download-network/scripts/dataset_download_probe.py probe --live
```

3. Choose the download method:
   - official CLI/SDK for platform-hosted datasets;
   - `aria2c` for raw large HTTP files with resume and multiple connections;
   - `curl -L -C -` as a conservative fallback;
   - DVC/DataLad/rclone for versioned or cloud-backed research datasets.
4. For mirrors, generate manifests on both sides and compare:

```bash
python3 skills/dataset-download-network/scripts/dataset_download_probe.py manifest ./official --hash sha256 --output official.jsonl
python3 skills/dataset-download-network/scripts/dataset_download_probe.py manifest ./mirror --hash sha256 --output mirror.jsonl
python3 skills/dataset-download-network/scripts/dataset_download_probe.py compare official.jsonl mirror.jsonl --mode exact
```

5. Save a download record in the project: source URL, platform, command, date, version/revision, proxy mode, manifest/hash result, and any mirror differences.

## Command Patterns

Hugging Face:

```bash
pip install -U "huggingface_hub[cli]"
hf download OWNER/DATASET --repo-type dataset --local-dir ./data/OWNER_DATASET
```

Raw HTTP fallback:

```bash
curl -L -C - --retry 20 --retry-delay 10 --connect-timeout 20 \
  -o ./data/raw/file.tar "https://example.org/file.tar"
```

aria2:

```bash
aria2c -c -x 8 -s 8 --max-tries=20 --retry-wait=10 \
  --auto-file-renaming=false -d ./data/raw "https://example.org/file.tar"
```

Git LFS:

```bash
GIT_LFS_SKIP_SMUDGE=1 git clone https://host/datasets/repo.git
cd repo
git lfs pull --include "train/*.parquet"
```

## References

For detailed rationale and current source links, read `references/current_practices_2026.md` only when needed.
