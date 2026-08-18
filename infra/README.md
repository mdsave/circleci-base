# infra

CDK stack for publishing and signing the `circleci-base` image.

Creates, in `tendo-marketplace` (`515909623945`, `us-east-1`):

- **ECR repository** `circleci-base` — scan-on-push, untagged images expire after 14 days, `RETAIN` on stack delete.
- **KMS key** (`ECC_NIST_P256`, `SIGN_VERIFY`) aliased `alias/cosign/circleci-base`, used by `cosign` to sign image digests. `RETAIN` on stack delete with a 30-day pending window.
- **IAM role** `circleci-base-publisher` (the stack itself is `circleci-base-ecr-publish`), assumable by:
  - Engineers whose SSO permission set matches `AWSReservedSSO_marketplace-admin_*` (always)
  - CircleCI via OIDC (`oidc.circleci.com/org/<org-id>`) — only when `circleciOrgId` is supplied

Automatic key rotation is not enabled: KMS supports it only for symmetric encryption keys, not asymmetric signing keys.

## Prerequisites

```bash
pnpm install
aws sso login --sso-session sso-session-oldhouse
```

## Deploy with SSO only

No CircleCI org ID needed. The role trusts your SSO permission set, which is
enough for `make docker-deploy` from a laptop:

```bash
make infra-diff
make infra-deploy
```

## Adding CircleCI OIDC

Supply `circleciOrgId` to also create the OIDC provider and a second trust
statement. Find the UUID in CircleCI under **Organization Settings → Overview**.
Deploying without it is not destructive — add it and redeploy at any time.

```bash
make infra-deploy CIRCLECI_ORG_ID=<uuid>
```

Optionally narrow CI trust to a single project (otherwise any project in the org
may assume the role):

```bash
make infra-deploy CIRCLECI_ORG_ID=<uuid> CIRCLECI_PROJECT_ID=<uuid>
```

If the account has never been bootstrapped for CDK:

```bash
pnpm exec cdk bootstrap aws://515909623945/us-east-1 --profile tendo-marketplace
```

## Outputs

| Output | Use |
| --- | --- |
| `RepositoryUri` | `IMAGE_NAME` for the root `Makefile` |
| `PublishRoleArn` | role for CircleCI to assume via OIDC |
| `CosignKeyUri` | `awskms:///alias/cosign/circleci-base`, passed to `cosign sign --key` |

## Signing with the key

Once deployed, sign against KMS instead of keyless (no public Rekor entry, and
works non-interactively in CI):

```bash
cosign sign --key awskms:///alias/cosign/circleci-base <repo-uri>@<digest>
cosign verify --key awskms:///alias/cosign/circleci-base <repo-uri>@<digest>
```

## Context defaults

Set in `cdk.json`; override with `-c key=value`.

| Key | Default |
| --- | --- |
| `account` | `515909623945` |
| `region` | `us-east-1` |
| `ecrRepoName` | `circleci-base` |
| `ssoPermissionSet` | `marketplace-admin` |
| `circleciOrgId` | _(optional — omit for SSO-only trust)_ |
| `circleciProjectId` | _(optional)_ |
| `tags` | ownership tags, see below |

## Ownership tags

`cdk.json` holds a `tags` object applied at stack scope, so every taggable
resource (ECR repo, KMS key, IAM role) inherits it. All six keys are required —
synth fails if any is missing or empty:

`TEAM_OWNER_NAME`, `TEAM_OWNER_EMAIL`, `PRODUCT_OWNER_NAME`,
`PRODUCT_OWNER_EMAIL`, `JIRA_PROJECT`, `SLACK_CHANNEL`, `PRODUCT_NAME`,
`PRODUCT_REPO`

Run `make infra-info` to see the current values.
