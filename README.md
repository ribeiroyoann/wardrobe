<div align="center">

# Wardrobe

Your clothes, extracted and organized with gpt-image.

[![License: MIT](https://img.shields.io/badge/license-MIT-191919?style=flat-square)](LICENSE)
[![Node 22+](https://img.shields.io/badge/node-22%2B-191919?style=flat-square)](package.json)

[See the original post →](https://x.com/cdngdev/status/2076812846793650485)

</div>

![Wardrobe gallery](docs/screenshots/gallery.png)

![Modeled wardrobe editor](docs/screenshots/editor.png)

## Quick start

```bash
git clone https://github.com/tandpfun/wardrobe.git
cd wardrobe
npm install
cp .env.example .env
npm run dev
```

⚠️ The importer stays disabled until you add `OPENAI_API_KEY` to `.env` and place an anonymous fit-model PNG at `data/fit-model-reference.png`.

Open [localhost:5173](http://localhost:5173).

## Import with Codex

This repo includes two Codex skills: one imports clothes and generates modeled item photos; the other styles complete outfits and generates a modeled lookbook.

```text
$import-clothes Import the clothes from ~/Pictures/outfits, create modeled photos, and add them to this wardrobe.
$generate-outfits Create modeled outfit ideas from my wardrobe.
```

Open the cloned repo in Codex and run either prompt. The import skill asks for a local anonymous fit-model PNG when needed, reviews every cutout and modeled photo, then writes to `data/library.json` and `data/imported/`. The outfit skill asks how many looks to create, then curates, generates, verifies, and saves the complete collection under `data/`.

### For agents

If you are setting up Wardrobe for a user, ask how they want to import their clothes:

- **Codex:** Ask for a folder or camera-roll location and an anonymous fit-model PNG, then extract, model, and import the individual pieces by following [the bundled import skill](.agents/skills/import-clothes/SKILL.md). Afterward, offer to create a requested number of modeled looks with [the outfit-generation skill](.agents/skills/generate-outfits/SKILL.md).
- **Web UI:** Help the user configure their own `OPENAI_API_KEY` and `data/fit-model-reference.png`, then let them import through the app.

## What it does

- Detects every garment in a photo with the OpenAI Responses API
- Extracts clean product cutouts with the OpenAI Images API
- Generates an optional modeled editorial preview
- Keeps originals, jobs, generated images, and the JSON database local in `data/`
- Supports drag, drop, paste, editing, review, regeneration, and approval

## Configuration

| Variable | Default |
| --- | --- |
| `OPENAI_API_KEY` | Required |
| `OPENAI_VISION_MODEL` | `gpt-5.4-mini` |
| `OPENAI_IMAGE_MODEL` | `gpt-image-2` |
| `OPENAI_IMAGE_QUALITY` | `high` |
| `WARDROBE_MODEL_REFERENCE` | `data/fit-model-reference.png` |
| `WARDROBE_DATA_DIR` | `data` |

## Personal VPS deployment

The canonical VPS workspace is `/home/yoann-dev/src/wardrobe`; immutable
releases and persistent data live under `/srv/personal-apps/wardrobe`.
Wardrobe binds only to `127.0.0.1:3210` and is published inside the tailnet at
`https://lcr-dev-vps.tailfe2d61.ts.net:8444`.

```bash
# Deploy the exact pushed commit checked out on the VPS
./scripts/deploy-vps.sh

# Roll back the application to the previous release (data is untouched)
./scripts/deploy-vps.sh rollback

# Runtime diagnostics
sudo docker inspect --format '{{.State.Health.Status}}' wardrobe
curl --fail http://127.0.0.1:3210/api/import/wardrobe
sudo tailscale serve status
sudo personal-vps-restic snapshots --tag wardrobe

# Preview, then pull canonical VPS data to Arch
./scripts/sync-vps-data.sh pull
./scripts/sync-vps-data.sh pull --apply

# Preview, then deliberately promote Arch data to the VPS
./scripts/sync-vps-data.sh push
./scripts/sync-vps-data.sh push --apply
```

Only `library.json`, `imported/`, and `fit-model-reference.png` are synchronized.
Each mutation backs up its destination and validates the JSON, asset counts,
paths, and checksums. Data restoration is always a separate, manual operation:
inspect an archive in `/srv/personal-apps/wardrobe/backups`, stop Wardrobe,
restore explicitly selected files, validate them, then restart and recheck the
API. Never restore data as part of an application rollback.

## License

[MIT](LICENSE)
