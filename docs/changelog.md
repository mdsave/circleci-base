# Changelog

Times are local (PDT), derived from build/tool output and file timestamps during
the session in which the change was made. Entries are newest-last.

## 2026-08-17

| Time | Change | Why |
| --- | --- | --- |
| 13:09 | Added `Makefile` with `build`, `validate` (hadolint), `trivy-config`, `trivy-fs`, `trivy-image`, `renovate`, `ci` | No build/scan entrypoint existed; every check was ad-hoc CLI invocation |
| 13:09 | Gave every target a `check-*` prerequisite that Homebrew-installs the missing tool | A fresh machine failed with bare "command not found" instead of a fix |
| 13:10 | First `trivy config` run surfaced 2 pre-existing HIGH Dockerfile findings (no `USER`, missing `--no-install-recommends` on `docker-ce`) | Recorded, not fixed — out of scope of the Makefile work |
| 13:17 | Diagnosed local build failure at `apt-key add` as Zscaler TLS interception, not a Dockerfile bug | `wget -q` swallowed the TLS error and piped empty input to `apt-key`, hiding the real cause |
| 14:47 | `Dockerfile`: optional `COPY zscaler-root-ca.cr[t]` + conditional `update-ca-certificates` | Lets local builds trust the corporate proxy; the bracket glob is a no-op in CI, so the published image is unchanged |
| 14:48 | `.gitignore`: added `zscaler-root-ca.crt`, `trivy-report.json` | Corporate CA must never ship in a public image; the report is a generated artifact |
| 14:48 | Rejected a second `Dockerfile.local`; consolidated to one Dockerfile | Two near-identical Dockerfiles would drift on every change |
| 15:16 | Added `zscaler-cert` target exporting the CA from the macOS keychain | The export command was a one-off incantation nobody would remember |
| 15:20 | `build`: added `--platform` defaulting to `linux/amd64` | Dockerfile pins the Docker apt repo to `arch=amd64`, so native arm64 builds fail on Apple Silicon |
| 15:23 | Added `copa` target (Copacetic): scan → patch OS packages → re-scan | Patch OS CVEs without waiting on a base-image rebuild |
| 18:00 | Enabled Docker Desktop containerd image store (manual, user-performed) | Copa needs BuildKit `mergeop`/`diffop`, unavailable on the default image store |
| 18:05 | `build`: added `--provenance=false --sbom=false` | Attestation manifests made the image a multi-entry index; Copa could not resolve a platform and failed |
| 21:36 | `copa`: treat "no package updates found" as success | Copa exits 0 but prints an error when nothing needs patching; the target failed on the *good* outcome |
| 21:55 | `trivy-fs` / `trivy-image`: added `--ignore-unfixed`; added informational `trivy-unfixed` | 2590 findings had no vendor fix, so the gate could never pass; the backlog is still visible on demand |
| 22:00 | Grouped `make help` into categories with ANSI colour headers | The flat list had grown past a screen |
| 22:10 | Added `docker-build`, `docker-start`, `docker-shell`, `docker-log`, `docker-stop` | Container lifecycle was manual `docker run` invocations |
| 22:15 | Added `docker-deploy`: ECR login → tag → push → `cosign sign` | Mirrors `.circleci/deploy` but targets the private ECR in `tendo-marketplace` and signs the artifact |
| 22:30 | Added `infra/` — CDK (TypeScript, plain `aws-cdk-lib`) creating the ECR repo, cosign KMS key, and publish role | Deploy target depended on resources nobody had defined as code |
| 22:35 | Made CircleCI OIDC optional; SSO is the base trust path | Allows deploying and publishing from a laptop without a CircleCI org ID |
| 22:40 | Added `infra-info`, `infra-install`, `infra-build`, `infra-synth`, `infra-diff`, `infra-deploy`, `infra-bootstrap` | Same rationale as the Docker targets: no memorised CLI incantations |
| 22:46 | Renamed the IAM role to `circleci-base-publisher` | It previously shared the exact name of the CloudFormation stack, which is ambiguous in logs and the console |
| 22:50 | Added `docker-status` with 🟢 / 🔴 / ⚪ states | "Down" alone does not distinguish "never created" from "exited" |
| 22:55 | Added `infra-clean` and `infra-undeploy` (prompts, warns what is retained) | Destroy keeps the ECR repo and KMS key but deletes the alias, which silently breaks the cosign key URI |
| 23:00 | Added ownership tags to `cdk.json`, applied at stack scope, required at synth, shown in `infra-info` | Ownership, cost attribution, and paging metadata on every resource |
| 23:03 | Added `PRODUCT_NAME` and `PRODUCT_REPO` tags | Requested; completes the tag set |
| 23:05 | Added this changelog and the top-level `README.md` | No entrypoint documentation existed |
| 23:20 | **branch 2.3**: added `-fL --retry 5 --retry-delay 2 --retry-all-errors` to both `curl` downloads in `Dockerfile` | A transient truncation of the 37 MB aptible `.deb` failed the build; `curl` retries nothing by default. `wget` calls left alone — they default to `--tries=20` |
| 23:40 | Confirmed the 2.3 slim image: 356 MB / 57 OS CVEs vs 671 MB / 2590 on 2.1.1 | Validates that package count, not OS version, drove the CVE count |
| 23:50 | Added `.trivyignore.yaml` (19 entries, path-scoped, `expiredAt: 2026-11-17`) | Vendor binaries statically link their Go deps; verified `apt` Candidate == Installed, so no fix exists to apply |
| 23:55 | Split the gate: `trivy-image` now `--pkg-types os` (hard fail); new `trivy-vendor` reports library findings without failing; `trivy-unfixed` bypasses the ignore file | The gate was permanently red on 44 CVEs in third-party binaries that nothing in this repo can fix |

## Known issues

| Item | Status |
| --- | --- |
| SSH host private keys baked into the image (`/etc/ssh/ssh_host_*`, `/usr/local/etc/ssh_host_*`) | **Open.** `service ssh restart` at build time generates them, so every container shares identical host keys. Found by `trivy-image` |
| Leftover `/openssh-9.3p1/` source tree | **Open.** Contains OpenSSH's public test fixtures, flagged as secrets. Harmless but noisy |
| Dockerfile has no `USER`; runs as root | **Open.** Flagged HIGH by `trivy config` |
| `docker-ce` install missing `--no-install-recommends` | **Open.** Flagged HIGH by `trivy config` |
| Ownership tag values copied from `workflow-engine` | **Unverified.** `TEAM_OWNER_*`, `PRODUCT_OWNER_*`, `JIRA_PROJECT`, `SLACK_CHANNEL` need confirmation |
| `cosign sign` uses keyless (public Rekor log) | **Open.** `infra` provisions a KMS key; `docker-deploy` should switch to `--key awskms:///alias/cosign/circleci-base` |
