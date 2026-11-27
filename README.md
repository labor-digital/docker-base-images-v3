# LABOR.digital Docker Base Images (v3)

Base images for LABOR projects: PHP + Apache (and Node, from phase 4).
Successor of [docker-base-images-v2](https://github.com/labor-digital/docker-base-images-v2).
Why v3 exists, and every design decision, are in [.design-log/001-v3-architecture.md](.design-log/001-v3-architecture.md).

Locale and timezone are preconfigured for Germany (`Europe/Berlin`, `en_US.UTF-8` + `de_DE.UTF-8`).

## Tags

Image: `labordigital/docker-base-images-v3`

| Tag | Meaning | Changes? |
|---|---|---|
| `php8.4`, `php84` | newest patch of PHP 8.4 | yes, with every upstream patch or security fix |
| `php-8.4.28` | exactly PHP 8.4.28 | never once published, use it to pin or roll back |
| `…-dev` (e.g. `php84-dev`) | same plus composer, git, mysql client, sudo, dev php.ini | as above |

Supported lines are whatever [docker-bake.hcl](docker-bake.hcl) lists. Lines past upstream end of life are no longer built.

Every tag is published for `linux/amd64` and `linux/arm64`, with an SBOM, build provenance and a keyless cosign signature:

```bash
cosign verify labordigital/docker-base-images-v3:php84 \
  --certificate-identity https://github.com/labor-digital/docker-base-images-v3/.github/workflows/release.yml@refs/heads/master \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
docker buildx imagetools inspect labordigital/docker-base-images-v3:php84 --format '{{json .SBOM}}'
```

## Using it in a project

Same contract as v2. Only `DOCKER_BASE_IMAGE` changes:

```
DOCKER_BASE_IMAGE=labordigital/docker-base-images-v3
DOCKER_BASE_TAG=php84
```

- `CMD` is `doppler run -- /opt/bootstrap.sh`. Override it with `/opt/bootstrap.sh` to run without Doppler.
- Project hooks (same as v2): `/opt/project/{bootstrap,build,development,directories,permissions}.sh`, `/opt/.env.app`.
- Environment: `PROJECT_ENV` (default `prod`), `APACHE_WEBROOT` (default `/var/www/html`), `DEFAULT_OWNER`, `DEFAULT_PERMISSIONS`.

### What changed compared to v2

- **TLS:** no certificate or key is baked into any image. Mount your own at `/var/cert/merged.crt` (certificate + key in one file); otherwise the container generates a self-signed one at first start. Dev images trust a root CA mounted at `/var/cert/ca.crt` (e.g. your `mkcert -CAROOT`/rootCA.pem).
- **Production images** no longer contain `sudo`, `vim`, `nano`, `zip` or `graphviz`. They are still in `-dev` except `zip`/`graphviz`.
- **Dropped extensions:** `mcrypt` (abandoned upstream). Dropped from `php82-dev`: xdebug.
- `LogLevel` is `notice` for every line (v2 php84 had `info`).

## Working on this repo

Requirements: Docker with buildx. Linters run from pinned images, so nothing else needs installing.

```bash
docker buildx bake --print                    # what would be built
docker buildx bake php84-base php84-dev --load
tests/smoke.sh labordigital/docker-base-images-v3:php-8.4.28 base 8.4.28
tests/smoke.sh labordigital/docker-base-images-v3:php-8.4.28-dev dev 8.4.28
```

Every change goes through a pull request: `feature/*`, `bugfix/*`, `renovate/*` → `master`, Conventional Commits, merge commits (no squash).
A code owner must approve (`.github/CODEOWNERS`). As a reviewer, also pull the PR, build it and run the smoke tests on your Mac (arm64), because CI only builds amd64 for pull requests.

### Auto lane: security updates without review

Upstream patch or digest updates of `php` / `node` (e.g. `8.4.28` → `8.4.29`, or a Debian rebuild of `8.4.28`) are merged by
Renovate itself once `pr` and `renovate-guard` are green, then released ([design log §4.1](.design-log/001-v3-architecture.md)).

- **`renovate-guard`** passes only for a diff that changes nothing but version rows in `docker-bake.hcl`, within the same minor,
  with digests that match Docker Hub right now (`scripts/renovate-guard.sh`, self-test in `tests/guard/`). Any other PR needs an
  approval from someone with write access on its current commit.
- **Trivy** in `pr.yml` fails only on a fixable CRITICAL that the published tag of that line does not already have.
- Every auto-merged release is logged on the open issue labelled `auto-lane`. Skim it weekly.

### Rollback

Point a moving tag back to an earlier immutable tag. The digest stays the same, so the signature stays valid:

```bash
docker buildx imagetools create -t labordigital/docker-base-images-v3:php84 labordigital/docker-base-images-v3:php-8.4.28
docker buildx imagetools create -t labordigital/docker-base-images-v3:php8.4 labordigital/docker-base-images-v3:php-8.4.28
```

Needs a Docker Hub login with push rights. The next release moves the tag forward again, so also revert or hold the change that caused it.

## One-time repository setup (GitHub admin)

Not automated on purpose; run once after creating the repository, then check the result in the GitHub UI.

```bash
REPO=labor-digital/docker-base-images-v3
gh repo create "$REPO" --public --description "LABOR.digital Docker base images (v3)"
gh api -X PATCH "repos/$REPO" -f allow_squash_merge=false -f allow_rebase_merge=false -f allow_merge_commit=true \
  -f delete_branch_on_merge=true \
  -F 'security_and_analysis[secret_scanning][status]=enabled' \
  -F 'security_and_analysis[secret_scanning_push_protection][status]=enabled'
# CODEOWNERS only counts teams with write access
gh api -X PUT "orgs/labor-digital/teams/developer/repos/$REPO" -f permission=push
gh api -X PUT "repos/$REPO/vulnerability-alerts"
gh api -X PUT "repos/$REPO/actions/permissions" -F enabled=true -f allowed_actions=selected -F sha_pinning_required=true
gh api -X PUT "repos/$REPO/actions/permissions/selected-actions" -F github_owned_allowed=true \
  -f 'patterns_allowed[]=docker/*' -f 'patterns_allowed[]=renovatebot/*' -f 'patterns_allowed[]=sigstore/*'
gh api -X PUT "repos/$REPO/actions/permissions/workflow" -f default_workflow_permissions=read -F can_approve_pull_request_reviews=false
# Workflows of fork PRs only run after a maintainer approves them (they could otherwise fake a check name)
gh api -X PUT "repos/$REPO/actions/permissions/fork-pr-contributor-approval" -f approval_policy=all_external_contributors
for f in .github/rulesets/*.json; do gh api -X POST "repos/$REPO/rulesets" --input "$f"; done
# Later changes to the JSON: update the existing ruleset by id instead of creating a second one
# id=$(gh api "repos/$REPO/rulesets" --jq '.[] | select(.name=="master-checks") | .id')
# gh api -X PUT "repos/$REPO/rulesets/$id" --input .github/rulesets/master-checks.json
```

Secrets and variables for Renovate: `vars.RENOVATE_APP_CLIENT_ID`, `secrets.RENOVATE_APP_PRIVATE_KEY`, and a read-only Docker Hub token as `secrets.DOCKERHUB_READ_USERNAME` / `secrets.DOCKERHUB_READ_TOKEN`.
### Publishing (`release.yml`)

On Docker Hub (org owner): create the public repository `labordigital/docker-base-images-v3` and an organization access token
with read/write on that repository only. Then store it in a `release` environment that only `master` can deploy from:

```bash
gh api -X PUT "repos/$REPO/environments/release" --input - <<'EOF'
{"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}
EOF
gh api -X POST "repos/$REPO/environments/release/deployment-branch-policies" -f name=master -f type=branch
gh secret set DOCKERHUB_USERNAME --env release --repo "$REPO"   # the user name that belongs to the token
gh secret set DOCKERHUB_TOKEN --env release --repo "$REPO"
```

## License

Apache-2.0, see [LICENSE.md](LICENSE.md).
