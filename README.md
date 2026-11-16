# opencode-sdlc

This repo is a personal OpenCode configuration, installed at `~/.config/opencode`
(`%USERPROFILE%\.config\opencode` on Windows). It defines seven agents, a global
permission baseline, and the skills those agents load.

## Principles

Machines do the work and run the checks. Humans own the verdict.

Automated tools can lint, typecheck, and run tests. They can catch syntax
errors, missing imports, and broken builds. They cannot catch a wrong
assumption, a misread requirement, or a diff that passes every check but
solves the wrong problem. That takes a person reading the change with fresh
eyes.

Every gate in this setup exists to make human review easier, not to replace
it:

- `review` checks the diff in a clean context and reports findings, but it
  does not merge.
- `ship` runs the checks and opens the PR, but it merges only after the
  wait script confirms the branch is safe.
- `ship` never uses `--admin`, so a branch protection rule that blocks the
  merge stops the run instead of being bypassed.
- The local branch stays after the merge. `ship` cannot delete it, because a
  pattern that allows `-d` also allows `-D` on Windows. The user decides
  when to clean up.

Automation handles the mechanical work: staging, committing, pushing, polling
for checks, merging, and syncing the trunk. Judgment stays with the human.

## Install

Put the repo at `~/.config/opencode`. On Windows that is
`%USERPROFILE%\.config\opencode`.

Restart OpenCode after you change an agent file. Sessions start in `plan`.
Switch agents with `tab`.

## OpenCode Go proxy

The agents call the `opencode-go` provider, which points at a Cloudflare Worker that
proxies OpenCode Go inference. The Worker URL and the Worker key come from
environment variables, so neither enters git. Built-in OpenCode free models are
disabled with `disabled_providers: ["opencode"]`.

### Proxy files

| Path | Role |
| --- | --- |
| `worker.js` | Cloudflare Worker that proxies Go inference to `https://opencode.ai/inference/go` |
| `opencode.jsonc` | Configures `opencode-go` against the Worker through `{env:...}` placeholders |
| `service.json` | Local, gitignored file with the service password and the `PROXY_BASE_URL` and `PROXY_KEY` environment |
| `service.json.example` | Tracked template for `service.json` |

The provider ID is `opencode-go`. `opencode.jsonc` sets `baseURL` to
`{env:PROXY_BASE_URL}` and `apiKey` to `{env:PROXY_KEY}`, with
`npm: "@ai-sdk/openai-compatible"`. `disabled_providers` contains `opencode`, so the
built-in free-model provider does not load. There is no manual `models` block.

### Provider settings

`PROXY_BASE_URL` is the Worker base URL including `/v1`. `PROXY_KEY` is the Worker
access key sent as `x-proxy-key` (or as a Bearer token). The Worker holds the
upstream OpenCode key as its `OPENCODE_API_KEY` secret and attaches it to every
request. `OPENCODE_DISABLE_FREE_MODELS` turns off the console free-model fetch.

### Set up the proxy

1. Deploy `worker.js` to the Worker bound to your custom domain. Nothing in the repo deploys it, so use the Cloudflare dashboard or Wrangler.
2. Add a `PROXY_KEY` secret to that same Worker in Cloudflare. Generate 32 random bytes:

   ```bash
   openssl rand -hex 32
   ```

   On Windows, the equivalent PowerShell expression is:

   ```powershell
   -join ((1..64) | ForEach-Object { '{0:x}' -f (Get-Random -Maximum 16) })
   ```

3. Add an `OPENCODE_API_KEY` secret to the Worker: the OpenCode API key it forwards upstream.
4. Copy `service.json.example` to `service.json`.
5. Set `password` to the local service password.
6. Set `PROXY_BASE_URL` to the Worker base URL including `/v1`, for example `https://<worker-host>/v1`.
7. Set `PROXY_KEY` to the same value as the Cloudflare secret.
8. Restart the service:

   ```powershell
   opencode service restart
   ```

9. Reload or restart OpenCode if the provider does not pick up the change.

`service.json` is gitignored. Never commit it. Other config changes reload
automatically. A change to the environment in `service.json` needs a restart.

### Verify the proxy

Replace `<worker-host>` with the Worker host and set `PROXY_KEY` in your shell.

```bash
curl -i "https://<worker-host>/v1/models"
curl -i -H "x-proxy-key: $PROXY_KEY" "https://<worker-host>/v1/models"
curl -i -X OPTIONS "https://<worker-host>/v1/models"
```

- `/v1/models` returns 401 without a key and with a wrong key. With the right key it returns 200 and the model list.
- `OPTIONS` returns 204.
- `GET /v1/unknown` returns 401 without a key, because the key is checked before the path.

Then check the provider in the TUI:

- `/models` shows the `opencode-go` models.
- A chat prompt against a Go model works.
- A 401 means `PROXY_KEY` does not match, or `OPENCODE_API_KEY` is missing or wrong in the Worker.
- No models means `/v1/models` failed or the provider did not reload.

For other protocols, send the request through the matching Worker path:

- `/openai/v1/chat/completions`
- `/openai/v1/responses`
- `/anthropic/v1/messages`
- `/google/v1beta/models/<model>:generateContent`

### Worker behavior

| Rule | Behavior |
| --- | --- |
| Routes | `/v1`, `/openai/v1`, `/anthropic/v1`, and `/google/v1beta` map to `https://opencode.ai/inference/go` |
| Auth | `x-proxy-key` (or `Authorization: Bearer`) must match the `PROXY_KEY` secret; a missing secret fails closed with 401 |
| Upstream key | Worker attaches `OPENCODE_API_KEY` as the upstream `Authorization` bearer; missing it returns 500 |
| Methods | `POST`, plus `GET` on paths ending in `/models`; `OPTIONS` answers 204 locally; other methods and paths are rejected |
| Limits | 32 MB request body, 5 minute upstream timeout |
| Stripped headers | `Host`, `cf-*`, `x-forwarded-*`, `x-real-ip`, `true-client-ip`, `cookie`, `origin`, `referer`, `x-opencode-client`, `x-client-version`, `x-proxy-key`, `authorization`, `x-api-key`, and other proxy or hop-by-hop headers |
| Upstream request | Browser User-Agent, and no CORS headers added to inference responses |
| Response | Upstream response headers are copied; only `set-cookie` is dropped, so `Retry-After` still reaches the client |

`worker.js` aborts the upstream request after five minutes. A stream longer than
five minutes is cut by design on the free plan. To raise the limit, raise the
Worker timeout and the provider timeouts in the same change.

### Cheap model checks

| Model | Protocol | Cost per million tokens |
| --- | --- | --- |
| `beam-free` | chat-completions | free |
| `qwen3.8-flash` | Anthropic messages | 0.15 input, 0.47 output |
| `muse-spark-1.2-contributor` | OpenAI responses | 0.10 input, 0.20 output |

These three cover the three protocols at the lowest cost. Skip `qwen3.8-max`,
`gemini-4-argon`, and `grok-4.7` for cheap tests. Send test messages and read the
responses through `/models` in the TUI, because both need the stored OpenCode
credential.

### Security

- Keep `service.json` untracked. It holds the service password and the Worker key.
- Rotate `PROXY_KEY` as soon as it is exposed, then update the Cloudflare secret and `service.json`.
- Keep `OPENCODE_API_KEY` only in the Worker; never put it in `service.json` or git.
- Add a Cloudflare WAF rate limit, and disable the workers.dev route when you do not use it.
- Never log the proxy key, the upstream API key, or the `Authorization` header.
- The Worker sends a browser User-Agent and strips client-identifying headers. Use it only where the provider terms allow that.

### Troubleshooting

| Symptom | Cause |
| --- | --- |
| 401 `Unauthorized` | `x-proxy-key` is missing or does not match the Cloudflare secret, or `OPENCODE_API_KEY` is missing or wrong in the Worker |
| 404 `Not found` | the path is outside the Worker route list |
| 405 `Method not allowed` | the request is not `POST` and not a `GET` on a `/models` path |
| 413 `Payload too large` | the request body exceeds 32 MB |
| 500 `Missing OPENCODE_API_KEY in worker env` | the Worker secret is not set |
| 502 `Upstream request failed` | the upstream request failed or timed out |
| Provider does not load | `PROXY_BASE_URL` is missing, or the service did not restart |
| No models | `/v1/models` failed, or the provider did not reload |

Rejected alternatives: keeping the old Go and Zen proxy plugin and catalog, the
Go/Zen model labels, and the multi-route worker no longer match this repo,
which proxies only OpenCode Go. Keeping the built-in `opencode` provider enabled
would leave the console free models in the picker.

## Agents

### Agent

| Agent | Use it for | Can edit |
| --- | --- | --- |
| plan | Requirements, design, and work breakdown; the default agent | Plan files under `.opencode/plan/` |
| build | Writing and refactoring code and config; it also commits on its short-lived branch | Code and config, but not `README.md`, `GLOSSARY.md`, `GLOSSARY-MAP.md`, or `docs/` |
| review | Pre-push verification and a commit message cross-check | Nothing |
| ship | Pushing, the pull request, the wait for checks, the squash merge, and the trunk sync; it commits only when the tree arrives uncommitted | Nothing; it writes git and `gh` state only |

### Sub Agent

| Agent | Use it for | Can edit |
| --- | --- | --- |
| branchwright | Creates the short-lived branch for another agent | Nothing; it writes git branch state only |
| verify | Runs lint, typecheck, and the test suite on demand and reports the evidence | Nothing |
| scribe | ADRs, glossary entries, README, and pages under `docs/` | `README.md`, `GLOSSARY.md`, `GLOSSARY-MAP.md`, and `docs/` |

## Flow

1. `plan` clarifies the request and records decisions through `scribe`. When the request is fuzzy it loads `grill-with-docs`, which runs the grilling interview and writes ADRs and glossary entries as decisions settle.
2. `build` dispatches `branchwright`, or cuts the short-lived branch itself when the subagent is unavailable, then edits, runs lint, and sends any docs work to `scribe`. When a change needs a test run, `build` can dispatch `verify`; the pre-push test gate still belongs to `review`.
3. `build` commits the change. `review` loads `requesting-code-review`, verifies the commits against the trunk in a fresh context, and cross-checks the conventional commit message.
4. `ship` loads `git-delivery`, pushes without a prompt, and opens the PR on the short-lived branch. It dispatches `branchwright` for an unbranched clean tree and commits only when the tree arrives uncommitted. It then waits for checks, squash-merges, deletes the merged branch, and syncs the trunk.
5. The merge is automated by `ship` with a squash merge and no `--admin`. A branch protection rule that blocks the merge stops the run instead of being bypassed.

## Human gates

1. `review` must pass before the push.
2. `ship` merges automatically with squash after the wait script returns ready.
3. A branch protection rule that blocks the merge stops the run.

## Docs

- [docs/workflow.md](docs/workflow.md): what each agent does and where it stops
- [docs/permissions.md](docs/permissions.md): how the permission rules work
- [docs/contributing.md](docs/contributing.md): adding agents, skills, and docs

`GLOSSARY.md` and `docs/adr/` are local-only development docs. They stay on disk
and are not in git.

Design notes live under `docs/`.
