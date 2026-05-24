# Security Notes

This toolbox is designed to be pushed to a public or private Git repository without carrying machine secrets.

## Do not commit

- real `config.yaml` for mihomo;
- proxy node definitions;
- subscription URLs;
- API tokens;
- SSH private keys;
- cookies;
- cloud credentials;
- datasets, checkpoints, model weights, or experiment outputs.

## Safe network pattern

Use tracked templates only:

- `network/mihomo/config.yaml.example`
- `network/mihomo/mihomo.env.example`

Keep real config in user-local paths:

- `~/.config/mihomo/config.yaml`
- `~/.local/state/mihomo/`

## Pre-push checks

```bash
git status --short
git grep -nE 'token|secret|password|passwd|cookie|Authorization|Bearer|subscription|proxy-provider' -- .
git ls-files | grep -E 'config.yaml$|\.env$|cache.db|\.mmdb|\.dat|\.metadb' || true
```

The grep can produce false positives in documentation. Investigate any match before pushing.
