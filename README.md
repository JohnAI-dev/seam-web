# seam-web

The Seam website. Static site in `site/`, built, fixed, reviewed and deployed automatically.

## How the autonomous cycle works

1. **Open an issue** (as the repo owner) describing a bug or a change.
2. **Grok engineer** (`.github/agent/grok_agent.py`) writes a fix and runs `scripts/test.sh`.
3. **Grok reviewer**, a separate call that only sees the issue, the diff and the test output, approves or rejects. Up to 3 attempts, with feedback fed back each time.
4. A PR is opened, **CI re-runs the tests** on a clean machine, and the PR is **squash-merged automatically**.
5. **Deploy** runs on prod1's self-hosted runner and publishes `site/` to `/var/www/seam-web`.

If the agent can't get an approved, passing fix, it comments on the issue instead.

## Controls

- Issues from other people are ignored until the owner adds the `agent` label.
- Add the `no-agent` label to an issue to keep the agent off it.
- Re-run on an issue: Actions → Grok agent → Run workflow → issue number.
- The agent can never modify `.github/` or `scripts/`, and tests run without access to secrets.

## Configuration

- Secret `XAI_API_KEY`: your xAI API key.
- Variable `XAI_MODEL` (optional): defaults to `grok-4.7`.
- prod1 setup: `scripts/setup-prod1.sh`.
