# Code Review Contract — circleci-base

## Author ↔ reviewer contract

CodeRabbit owns line-level review: this is the **CI base image for the whole
MDsave estate**, so review here is a supply-chain review — package pinning, key
provenance, unchecksummed downloads, and base-image changes that propagate to
every repo's CI at once. Humans own architecture, product fit, and risk.
**Respond to every CodeRabbit comment** — a dismissal should say why, not be
silent, since "not valid" is itself a signal that a rule needs tightening.

**There is no safety net in this repo.** `master` holds a `Dockerfile`, a
`Vagrantfile`, `dev/init` and `.github/CODEOWNERS` — no CI config, no tests, no
build script. The only verification a change gets is that the image builds, and
the blast radius of a bad change is every CI job in the estate. Review
accordingly.

## Org-wide baseline rules (always present)

These two apply to every repo regardless of what it mines, and are not
optional: **PHI/PII audit logging** (flag code that logs/prints/persists
patient-identifying info — including but not limited to name, DOB, MRN, SSN,
insurance/member ID, email address, phone number, or physical address — without
an approved audit-logging wrapper or de-identification step) and
**secrets/credentials** (flag any hardcoded credential/key/token/password,
reinforcing but not replacing `gitleaks`). They come from
`coderabbit-baseline.yaml`, not this repo's own docs — CodeRabbit's org-wide
settings for these do not merge with a repo's own yaml (`inheritance` confirmed
to have zero effect), so encoding them here is the only way they survive on a
repo with its own config. Never omit this section.

A build image is a plausible place for a credential to be baked into a layer,
so the secrets rule is not idle here even though the repo stores no data.

## Hard rules

Every example below is from the Dockerfile as it stands today, not invented.

**Pin what is load-bearing.** An unpinned install means the image changes
silently on whatever day it is next rebuilt.
- Bad: `RUN apt-get install -y docker-ce` — the Docker version in the CI image is whatever upstream serves that day
- Good: `RUN apt-get install -y docker-ce=<pinned version>`

**Keys go in `/etc/apt/keyrings`, not the global trusted set.** `apt-key add`
is deprecated, and a key added that way can sign packages from *any* configured
repo, not just the one it was added for.
- Bad: `RUN wget -qO - https://download.docker.com/linux/ubuntu/gpg | apt-key add -`
- Good: `RUN wget -qO /etc/apt/keyrings/docker.asc https://download.docker.com/linux/ubuntu/gpg` plus `signed-by=/etc/apt/keyrings/docker.asc` on the sources entry

**A fetched executable needs a pinned version, ideally a checksum.** The
existing `docker-compose` fetch is the pattern to keep — pinned — not the
version to copy; 1.11.2 is ancient.
- Bad: `RUN wget -nv -O /usr/bin/foo "https://example.com/foo/latest/foo-$(uname -s)-$(uname -m)"`
- Good: a pinned tag plus a verified `sha256sum` before `chmod +x`

**No trailing space after a line-continuation backslash.** It turns the
continuation into an empty line instead of a join, and it fails silently.
- Bad: `    libffi-dev \ ` — this is live at line 25 today
- Good: `    libffi-dev \`

**A base-image bump is a breaking change, not a chore.** The current base
(`ailispaw/ubuntu-essential:14.04-nodoc`) is long EOL, so bumping is
*desirable* — but it changes the toolchain under every downstream CI job.
- Bad: base image bumped in a PR titled "cleanup", no mention in the description
- Good: the bump is the PR's stated purpose, with the downstream impact named and a plan for which repos verify first

**`dev/init` and `Vagrantfile` must not drift from the Dockerfile.** They are
the local entry points, nothing in this repo exercises them, so drift surfaces
only when someone next builds locally.
- Bad: a package added to the `Dockerfile` and not to `dev/init`, or vice versa
- Good: both updated in the same commit, or a comment saying why only one applies

## Known, explicitly out of scope

- **"The branch name IS the image tag" does not apply to this repo the way it
  does to `regression-testing`.** The estate-wide warning is that CI replaces
  `/` with `-` when deriving an image tag, so `story/FEAT-1/MDS-2` and
  `story/FEAT-1-MDS-2` collide on one tag. Here, `master` carries **no CI at
  all**; the only `.circleci/deploy` lives on the old release branches
  `2.1`–`2.4`, and it tags with the raw `$CIRCLE_BRANCH` and no sanitisation —
  so a branch containing `/` would simply fail the tag/push (Docker disallows
  `/` in a tag component) rather than silently colliding. Do not encode a
  `path_instructions` rule for a collision that cannot happen here.

  *Evidence note:* the `master` half of this (no CI config, `.github` holding
  only CODEOWNERS) was verified directly. The release-branch detail comes from
  a read of branches `2.1`–`2.4` and has not been independently re-read since —
  re-check it before relying on it for anything load-bearing.

- **The EOL base image is known, not a finding to re-raise every PR.**
  `ubuntu-essential:14.04-nodoc`, `python-software-properties` and
  docker-compose 1.11.2 are all stale. That is understood; flag them when a PR
  *touches* them, don't re-report the standing state on every unrelated diff.

## Calibration status

`request_changes_workflow: false` — calibrating, not yet flipped.
`review_details: true` is on deliberately, to surface comments the `chill`
profile would otherwise suppress while the rules are being tuned.

**GitHub merge-gate mechanism.** This repo is on GitHub
(`github.com/mdsave/circleci-base`), where the gate genuinely works — but only
for a **failing pre-merge check in `error` mode**, never for a path-instruction
finding alone, however severe. Current check modes:

| check | mode |
|---|---|
| `issue_assessment` | `warning` |
| `title` | `warning` |
| `description` | `warning` |
| `docstrings` | `off` |

`master`'s actual branch protection, read from the API on 2026-09-10:

| setting | value |
|---|---|
| required approving reviews | **1** |
| code-owner review required | **true** |
| require conversation resolution | **false** |
| required status checks | **none — the contexts list is empty** |

Two consequences worth stating plainly. Conversation resolution is *off*, so an
unresolved CodeRabbit thread does not hold the merge. And because the required
status-checks list is **empty**, flipping a CodeRabbit check to `error` mode
would not gate anything on its own — the check has to be *added to required
status checks* as well. That is a repo-settings change, not a `.coderabbit.yaml`
change, and it is the actual prerequisite for the flip.

On the current Pro plan, `custom_checks` are capped at 0 and never execute as
their own named check. The supply-chain rules above would have been a natural
custom check; they were mined into the `Dockerfile` `path_instructions` entry
instead, not left as a non-functional `custom_checks` block.

The remaining flip, once the checks above have a clean run of low false
positives: add the chosen check to `master`'s required status checks, set
`request_changes_workflow: true`, and flip that check to `error`.
