# circleci-base

Base Docker image used as the CircleCI executor for Tendo builds. Ubuntu 22.04
with git, Docker CE, docker-compose, Ruby + aptible-cli, AWS CLI v2, jq, and
OpenSSH 9.3 built from source.

The image is built from [`Dockerfile`](Dockerfile) and published per branch —
the branch name is the image tag (see [`.circleci/deploy`](.circleci/deploy)).

## Quick start

```bash
make help          # all targets, grouped
make build         # build the image locally
make ci            # validate + trivy + renovate
```

## Documentation

| Document | Contents |
| --- | --- |
| [infra/README.md](infra/README.md) | CDK stack: ECR repository, KMS signing key, publish role |
| [docs/changelog.md](docs/changelog.md) | What changed, when, and why |

## Make targets

`make help` is the source of truth. Summary:

| Group | Targets |
| --- | --- |
| Build | `build` |
| Validate | `validate` (hadolint) |
| Container lifecycle | `docker-build`, `docker-start`, `docker-shell`, `docker-status`, `docker-log`, `docker-stop`, `docker-deploy` |
| Infrastructure | `infra-info`, `infra-install`, `infra-build`, `infra-synth`, `infra-diff`, `infra-deploy`, `infra-undeploy`, `infra-bootstrap`, `infra-clean` |
| Security scanning | `trivy`, `trivy-config`, `trivy-fs`, `trivy-image`, `trivy-unfixed` |
| Remediation | `copa` |
| Dependency updates | `renovate` |
| Local dev setup | `zscaler-cert` |
| Aggregate | `ci` |

Every target that shells out to a tool has a `check-*` prerequisite that installs
the tool via Homebrew when missing, so a fresh machine does not fail with
"command not found".

## Local build requirements

Two environment quirks affect local builds but not CI:

**Apple Silicon.** The Dockerfile pins the Docker apt repository to
`arch=amd64`, so a native `arm64` build fails at the `docker-ce` step. `make
build` therefore defaults to `PLATFORM=linux/amd64`, matching what CI publishes.
Builds run under emulation and take roughly 8-10 minutes cold.

**Corporate TLS interception (Zscaler).** Build containers do not inherit the
host's certificate trust, so the Dockerfile's HTTPS fetches fail behind Zscaler.
Export the root CA once:

```bash
make zscaler-cert   # writes zscaler-root-ca.crt (git-ignored)
```

The Dockerfile picks it up through an optional `COPY zscaler-root-ca.cr[t]` —
a glob that copies nothing when the file is absent, so CI is unaffected.

**containerd image store.** `make copa` requires BuildKit's `mergeop`/`diffop`,
available only with Docker Desktop's containerd image store enabled
(Settings → General → "Use containerd for pulling and storing images").

## Security scanning

Scanning is split by whether a finding is actionable in this repo:

| Target | Scope | Fails the build? |
| --- | --- | --- |
| `trivy-image` | OS packages + secrets | **yes** — we choose what the Dockerfile installs |
| `trivy-vendor` | vendor binaries (`gobinary`, `python-pkg`) | no — fixed only by the vendor rebuilding |
| `trivy-unfixed` | everything, ignore file bypassed | no |

Third-party binaries (`docker`, `docker-buildx`, `docker-compose`, `yq`) ship
their Go dependencies statically linked, so a Go stdlib CVE in them cannot be
fixed by `apt` or by Copa — only by the vendor recompiling. Those findings are
recorded in [`.trivyignore.yaml`](.trivyignore.yaml) with a `statement` and an
`expiredAt` date, which keeps `trivy-vendor` quiet until something *new* appears.

Note that trivy only auto-detects `.trivyignore`, so the YAML form is passed
explicitly via `--ignorefile`; running bare `trivy` will not apply it.

On expiry, rebuild and run `make trivy-unfixed` (which bypasses the ignore file)
to see whether upstream has shipped fixes, then prune the file.

`make copa` patches OS packages in place with
[Copacetic](https://project-copacetic.github.io/copacetic/) and re-scans. It
exits cleanly when there is nothing to patch.
