# Code Review Contract — circleci-base

## Author ↔ reviewer contract

CodeRabbit owns line-level review: this is the **CI base image the whole MDsave
estate executes from**, so review here is a supply-chain review — pinning,
key provenance, unchecksummed downloads, architecture assumptions, and the
deploy scripts that push to ECR. Humans own architecture, product fit, and
risk. **Respond to every CodeRabbit comment** — a dismissal should say why, not
be silent, since "not valid" is itself a signal that a rule needs tightening.

**There is no test suite.** CI builds the image and pushes it; nothing asserts
the image works. So the only verification a change gets is that it builds,
while the blast radius of a bad change is every CI job in the estate.

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

The `.circleci/` scripts hold credentials that can push to ECR, so the secrets
rule is not idle here.

## Hard rules

Every example below is from the tree as it stands after the `2.4` merge.

**Pin what is fetched.** An artifact resolved at build time changes the image
on whatever day it is next rebuilt.
- Bad (all three live today): `ENV URL=".../aptible/omnibus-aptible-toolbelt/latest/aptible-toolbelt_latest_ubuntu-1604_amd64.deb"`; `wget -nv -O /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64`; `curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"`
- Good (live): `wget https://github.com/stedolan/jq/releases/download/jq-1.8.0/jq-linux64` — an exact release tag

**Verify what is downloaded.** None of the four fetches above checks a checksum
or signature. This is the standing state — raise it when a PR *touches* one of
those lines or adds a fifth, not on every unrelated diff.
- Bad: a new `wget`/`curl` of an executable, then straight to `chmod +x`
- Good: a pinned URL plus a verified `sha256sum -c` before `chmod +x`

**Keys go in `/etc/apt/keyrings`, not the global trusted set.** `apt-key add`
is deprecated, and a key added that way can sign packages from *any* configured
repo, not just the one it was added for.
- Bad (live at line 35): `RUN wget -qO - https://download.docker.com/linux/ubuntu/gpg | apt-key add -`
- Good: write the key to `/etc/apt/keyrings/docker.asc` and add `signed-by=/etc/apt/keyrings/docker.asc` to the sources entry

**Pin load-bearing apt packages.** The Docker client in CI currently moves with
upstream on every rebuild.
- Bad (live): `apt-get install -y docker-ce-cli docker-buildx-plugin docker-compose-plugin`
- Good: the same three with exact `=<version>` constraints

**Single-architecture assumptions are a real constraint, not an oversight to
"fix" silently.** `x86_64`/`amd64` is hardcoded for the AWS CLI, `yq` and the
aptible deb — and changing where this image can build is not a local decision.
- Bad: adding a fourth `amd64`-only fetch without saying so
- Good: call it out in the PR description, or parameterise on `$(dpkg --print-architecture)`

**A base-image bump is the PR's purpose, never a side effect.** It changes the
toolchain under every downstream CI job.
- Bad: base bumped in a PR titled "cleanup", unmentioned in the description
- Good: the bump is the stated purpose, with downstream impact named — as the `2.4` merge did when it moved to `ubuntu:24.04`

**Comments must not outlive the code beside them.**
- Bad (live): `# install jq 1.5` sitting above a fetch of `jq-1.8.0`
- Good: the comment names the version actually fetched, or names none

**`:current` is the Aikido scan anchor and stays gated on the release branch.**
- Bad: publishing `:current` unconditionally, which would point the security scan at an arbitrary branch's image
- Good (live in `.circleci/deploy`): `if [ -n "$RELEASE_BRANCH" ] && [ "$CIRCLE_BRANCH" = "$RELEASE_BRANCH" ]` before the `docker tag`/`docker push`

## Known, explicitly out of scope

- **The estate-wide "branch name IS the image tag" collision does not apply
  here — but a different failure of the same family does.** The `regression-testing`
  warning is that CI replaces `/` with `-` when deriving a tag, so
  `story/FEAT-1/MDS-2` and `story/FEAT-1-MDS-2` collide on one tag. Here,
  `.circleci/deploy` tags with the **raw** `$CIRCLE_BRANCH`
  (`docker build -t "$IMAGE:$CIRCLE_BRANCH"`) and performs **no sanitisation at
  all**, and the workflow carries no branch filter. A Docker tag component
  cannot contain `/`, so a `type/slug` branch name cannot produce a valid tag
  here — it would fail rather than collide.

  *Evidence note:* that is a **static** reading of `.circleci/deploy` and
  `.circleci/config.yml`. It has **not** been confirmed dynamically — CircleCI
  posts no status check on pull requests in this repo (the only check on PR #5
  is CodeRabbit's), so whether the job actually runs for a given branch could
  not be observed from the PR. Confirm against a real CircleCI run before
  treating it as settled.

- **The standing unpinned/unchecksummed fetches are known.** The three
  build-time-resolved artifacts and the absence of any checksum are recorded
  above as rules to apply when a PR touches them — not as findings to re-raise
  on every unrelated diff.

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

`master`'s branch protection, read from the API on 2026-09-10:

| setting | value |
|---|---|
| required approving reviews | **1** |
| code-owner review required | **true** |
| require conversation resolution | **false** |
| required status checks | **none — the contexts list is empty** |

Two consequences. Conversation resolution is off, so an unresolved CodeRabbit
thread does not hold the merge. And because the required status-checks list is
**empty**, flipping a CodeRabbit check to `error` would not gate anything on its
own — the check must also be *added to required status checks*. That is a
repo-settings change, not a `.coderabbit.yaml` change, and it is the real
prerequisite for the flip.

On the current Pro plan, `custom_checks` are capped at 0 and never execute as
their own named check. The supply-chain rules above would have been the natural
custom check; they were mined into the `Dockerfile` and `.circleci/**`
`path_instructions` entries instead, not left as a non-functional
`custom_checks` block.

The remaining flip, once the checks above have a clean run of low false
positives: add the chosen check to `master`'s required status checks, set
`request_changes_workflow: true`, and flip that check to `error`.
