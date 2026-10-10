# seam-web

The Seam website. Static site in `site/`, built, fixed, reviewed and deployed automatically.

## How the autonomous cycle works

1. **Open an issue** (as the repo owner) describing a bug or a change.
2. **Grok engineer** (`.github/agent/grok_agent.py`) writes a fix and runs `scripts/test.sh`.
3. **Grok reviewer**, a separate call that only sees the issue, the diff and the test output, approves or rejects. Up to 3 attempts, with feedback fed back each time.
4. A PR is opened, **CI re-runs the tests** on a clean machine, and the PR is **squash-merged automatically**.
5. **Deploy** is pull-based: CI moves the `live` branch to the tested commit, and the seamweb
   web server (an isolated VM) fetches it and serves it; Cloudflare Tunnel publishes it as https://seamweb.no.
   Nothing connects in to the server.

If the agent can't get an approved, passing fix, it comments on the issue instead.

## Controls

- Issues from other people are ignored until the owner adds the `agent` label.
- Add the `no-agent` label to an issue to keep the agent off it.
- Re-run on an issue: Actions → Grok agent → Run workflow → issue number.
- The agent can never modify `.github/` or `scripts/`, and tests run without access to secrets.

## Configuration

- Secret `XAI_API_KEY`: your xAI API key.
- Variable `XAI_MODEL` (optional): defaults to `grok-4.7`.
- Hosting: an isolated VM that pulls the `live` branch; published through Cloudflare Tunnel.

## Agent cost controls

Every LLM call logs its tokens and cost (from the API's own usage report) in the job log and
the job summary, and the spend is recorded on the `agent-ledger` branch. Repository variables
(Settings → Secrets and variables → Actions → Variables) tune it; defaults in brackets:

- `AGENT_BUDGET_ISSUE_USD` [2]: no new call once an issue has used this. Re-adding the `agent`
  label gives it a fresh budget.
- `AGENT_BUDGET_DAY_USD` [10]: per repository and UTC day; waiting issues continue the next day.
- `AGENT_MAX_ATTEMPTS` [3] per run, `AGENT_MAX_FAILED_RUNS` [1] automatic re-runs of a failed issue.
  CI/merge failures, crashes, timeouts and budget stops wait for a human.
- `AGENT_MAX_CONTEXT_BYTES` [80000]: the engineer sees the file tree plus the files named in the
  issue and up to 12 picked by a cheap selection call, not the whole repository.
- `AGENT_REASONING_EFFORT` [medium], `XAI_REVIEW_MODEL` / `XAI_SELECT_MODEL` [grok-build-0.1;
  falls back to `XAI_MODEL` if unavailable].
