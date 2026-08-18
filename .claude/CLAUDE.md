# CLAUDE.md

## What this repo is

One Docker image — the base CI executor for Tendo/MDsave builds — plus the CDK
stack that hosts and signs it. There is no application code and no test suite;
the artifact is the image. `Dockerfile` is the product, `Makefile` is the
entrypoint, `infra/` provisions the publish target.

Remote is GitHub (`mdsave/circleci-base`), not Bitbucket — the Bitbucket
conventions in the global CLAUDE.md do not apply here.

## Layout

| Path | Role |
| --- | --- |
| `Dockerfile` | the image; single source, no variants (see below) |
| `Makefile` | build / lint / scan / publish / infra targets, `make help` is authoritative |
| `.circleci/` | the CircleCI job that publishes to **public** ECR on every branch push |
| `infra/` | CDK (TypeScript, plain `aws-cdk-lib`): private ECR repo, cosign KMS key, publish role |
| `docs/changelog.md` | why each change was made; newest-last, `Known issues` table at the bottom |
| `dev/`, `Vagrantfile` | dead since 2017 (Vagrant + Docker 1.13.1). Do not extend or "fix" |

## Commands

```bash
make help            # grouped list of every target
make build           # PLATFORM=linux/amd64 by default
make ci              # validate + trivy + renovate
make docker-shell    # interactive shell in the built image
make infra-info      # resource names/tags the CDK stack will create (no AWS needed)
```

`infra/` uses **pnpm** (`pnpm exec cdk ...`), never npm. AWS work needs
`aws sso login --sso-session sso-session-oldhouse`; profile is
`tendo-marketplace` (account `515909623945`, `us-east-1`).

## Branch is the image tag — check the branch before changing anything

`.circleci/deploy` pushes `public.ecr.aws/g8w4z0q4/circleci-base:$CIRCLE_BRANCH`,
and `make docker-deploy` tags the private ECR image with
`git rev-parse --abbrev-ref HEAD`. Tags are mutable, so **pushing to a branch
republishes that tag under every consumer already pinned to it.**

`master` is stale: its tree is only `Dockerfile`, `Vagrantfile`, `dev/`,
`.github/`, `.gitignore`. Active work happens on the numbered release branches
(`1.1` … `2.3`); `2.3` is the current line and is ~37 commits ahead of `master`.
The `Makefile`, `README.md`, `docs/`, and `infra/` exist only on that line. Do
not assume `master` reflects what consumers run, and do not target `master` with
a PR without asking.

Two publish paths exist and they are not equivalent:

- **CI** → public ECR (`public.ecr.aws/g8w4z0q4`), unsigned, static AWS keys.
- **`make docker-deploy`** → private ECR in `tendo-marketplace`, then
  `cosign sign`. Note it still signs **keyless** despite `infra/` provisioning a
  KMS key; switching it to `--key awskms:///alias/cosign/circleci-base` is an
  open item in `docs/changelog.md`.

## `make ci` does not pass today

Verified: `make trivy-config` exits 1. Two independent causes —

1. `Dockerfile` HIGH findings: no `USER` (runs as root), a bare
   `apt-get update` step, and the `docker-ce-cli` install missing
   `--no-install-recommends`.
2. `trivy config .` walks `infra/node_modules`, so vendored `aws-cdk-lib`
   CloudFormation templates contribute findings that have nothing to do with
   this repo.

Do not report "CI is green" off `make ci`. Run the specific target that covers
your change (`make validate`, `make trivy-image`, `make infra-build`) and say
which one you ran.

## Dockerfile conventions

- **One Dockerfile.** A separate `Dockerfile.local` was proposed and explicitly
  rejected — two near-identical files drift. Local-only needs go in behind a
  no-op, like the optional `COPY zscaler-root-ca.cr[t]` bracket glob that copies
  nothing when the (git-ignored) cert is absent, leaving CI unaffected.
- **Stay slim.** Recent work cut the image ~871MB → ~350MB by dropping the Ruby
  toolchain, `build-essential`, and the full `docker-ce` engine. Add packages
  only with a stated consumer.
- **Removing a tool is a cross-repo change.** Downstream repos call these
  binaries directly — e.g. `yq` exists solely because `mdsave2`'s
  `.circleci/deploy` needed a YAML→JSON step after system Ruby was removed. Grep
  the consuming repo before deleting anything.
- CI runs against `setup_remote_docker`, so only the Docker **client** +
  `buildx` + `compose` plugins belong here, not the engine.
- Network fetches use `curl -fL --retry 5 --retry-delay 2 --retry-all-errors`;
  a silent `wget -q` once masked a TLS failure as an `apt-key` bug.
- Apple Silicon: the Docker apt repo is pinned `arch=amd64`, so native arm64
  builds fail. `make build` forces `linux/amd64` (8–10 min cold under emulation).

## infra/ conventions

- Config lives in `cdk.json` `context`, not in code; override with `-c key=value`
  (the Makefile threads `CIRCLECI_ORG_ID` / `CIRCLECI_PROJECT_ID` through this way).
- The eight ownership tags are **required at synth** — `bin/app.ts` throws if any
  is missing. Values were copied from `workflow-engine` and are still unverified.
- ECR repo and KMS key are `RETAIN`. `infra-undeploy` deletes the KMS *alias*,
  which silently breaks `awskms:///alias/cosign/circleci-base`; the target prints
  this before prompting.
- CircleCI OIDC trust is optional — SSO is the base path, so the stack deploys
  and publishes from a laptop without a CircleCI org ID.

## Docs

`docs/changelog.md` records **why**, one row per change with a local timestamp,
newest-last, plus a `Known issues` table. Update it when you change behavior.

`README.md` is stale in its opening paragraph: it still claims Ubuntu 22.04 with
Ruby and OpenSSH 9.3 built from source. The image is Ubuntu 24.04, Ruby is gone
(aptible-cli ships its own embedded Ruby), and OpenSSH comes from the `ssh`
package — which also retires the changelog's SSH-host-key and
`/openssh-9.3p1/`-source-tree known issues.
