# circleci-base

The CircleCI executor image for MDsave build, test and deploy jobs, published to
`public.ecr.aws/g8w4z0q4/circleci-base`; a repo adopts it by naming a tag on an executor's `image:` line.
It is Ubuntu 24.04 plus the command line those jobs call — the Docker client with `buildx` and the
`docker compose` plugin, AWS CLI v2, `aptible-cli`, `git`, `jq`, `yq`, `curl` — and nothing else: no
Docker engine (jobs use the remote daemon from `setup_remote_docker`), no Node, no Ruby. The
[`Dockerfile`](Dockerfile) is the whole inventory; [`REVIEW.md`](REVIEW.md) holds the review rules.
Every job and parallel container pulls it (about 8 pulls per mdsave2 pipeline), so size is paid in
"Spin up environment" time; the `2.3` slimming dropped the AWS CLI installer leftovers, Apollo and
Node, the full `docker-ce` engine, the standalone `docker-compose` binary and the Ruby toolchain.

## Publishing: the branch name is the tag

`.circleci/deploy` runs `docker build -t "$IMAGE:$CIRCLE_BRANCH" .` and `docker push`, and the
workflow has no branch filter, so **every branch you push publishes a tag named after itself**. There
is no release step. (This repo's own jobs run on `cimg/node`; ECR credentials come from the
`<env>/env-secrets` secret via `.circleci/configure-env`.)

- **Never change a branch whose tag a consumer pins.** A push to it, or a re-run of its workflow,
  rebuilds and republishes the tag in place, and every consumer pinned to it gets the new image the
  next time it pulls. A rebuild is not reproducible: the AWS CLI zip, `yq`, the aptible `.deb`, the
  Docker apt packages and `apt-get upgrade` all resolve to latest on the day (`REVIEW.md`), so even an
  untouched commit can ship a different image. To ship a change, cut a new version branch (`2.5` after
  `2.4`; `master` already contains `2.4`) and let consumers opt in.
- **Test on a throwaway branch, not by re-running a release branch.** It publishes a tag nothing
  consumes. The name must be a legal Docker tag, so no `/`: `docker` rejects `chore/x` with `invalid
  reference format`. There is no test suite, so a green CircleCI build of the branch is the only gate,
  and a local `docker build` is no substitute behind a TLS-intercepting proxy (Zscaler): the
  Dockerfile has no hook for the proxy's root CA, so HTTPS downloads fail with `curl: (60) SSL
  certificate problem: unable to get local issuer certificate` (seen 2026-10-01).
- **`:current` is not a version.** `.circleci/deploy` also tags it, but only on the branch named in
  [`RELEASE`](RELEASE) (`2.4` today), as the one stable record Aikido scans so triage survives a
  release. Nothing should pin it; a new release sets `RELEASE` to its own name.
- Clone and push over https (the URL in tendo-marketplace's `bin/repos.manifest`): one engineer's SSH
  push was refused here in 2026-09 while https worked (not re-tested).

## Who pins which tag

A consumer opts in by editing the tag on its executor's `image:` line. From each repo's trunk on
2026-10-01:

| repo | tag | executor |
|---|---|---|
| mdsave2 (`preview`, `staging`, `master`) | `2.4` | `base-config` in `.circleci/config.yml` |
| maintenance-jobs (`main`) | `2.2` | `base-config` in `.circleci/config.yml` |
| regression-testing (`main` only) | `2.1` | `mdsave-config`; `preview` and `staging` do not use this image |

mdsave-api, frontend and claims-processing run on `cimg/*` images. Re-check any time with
`git grep -n -F 'circleci-base:' origin/<trunk> -- .circleci`.

**Read what a tag dropped before adopting it.** `2.3` and later have no system Ruby, Node or Apollo.
mdsave2 adopted `2.3` in one commit (`9194191bcf2`) that also replaced the `ruby -ryaml -rjson` call in
its `.circleci/deploy` with `yq -o=json '.' .mdsave.yml`, since a bump alone would have broken that
call. `aptible-cli` is unaffected: it installs from the omnibus `.deb`, which carries its own Ruby
(`/opt/aptible-toolbelt/embedded/bin/ruby`), and `aptible version` runs on a tag with no system Ruby.
Check a tag directly:

    docker run --rm --platform linux/amd64 --entrypoint sh public.ecr.aws/g8w4z0q4/circleci-base:2.4 \
      -c 'aptible version; yq --version; docker compose version; command -v ruby || echo "no system ruby"'

**Coverage gap when a consumer bumps the tag.** A bump branch runs the consumer's build and test jobs
on the new image, but only a branch matching a deploy filter runs its deploy job, so a change to the
consumer's deploy script (its `aptible`, `aws`, `yq`, `jq` and `docker` calls) is not exercised before
merge. mdsave2's deploy jobs run only on `master`, `staging`, `demo`, `preview`, `feature-beta`,
`feature-*` and `redox`/`prodtesting`, and on any other branch `.circleci/pre-build` cancels the
workflow unless the commit subject contains `[ci build]`. The first real exercise is therefore the
post-merge `deploy-preview`. Exercising deploy earlier means a `feature-*` branch, which provisions
(and bills) a real ephemeral environment — decide that on purpose.
