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
  -f 'patterns_allowed[]=docker/*' -f 'patterns_allowed[]=renovatebot/*'
gh api -X PUT "repos/$REPO/actions/permissions/workflow" -f default_workflow_permissions=read
for f in .github/rulesets/*.json; do gh api -X POST "repos/$REPO/rulesets" --input "$f"; done
```

Secrets and variables for Renovate: `vars.RENOVATE_APP_CLIENT_ID`, `secrets.RENOVATE_APP_PRIVATE_KEY`, and a read-only Docker Hub token as `secrets.DOCKERHUB_READ_USERNAME` / `secrets.DOCKERHUB_READ_TOKEN`.
The push token for Docker Hub comes with the release workflow (phase 3) and lives in a `release` environment.

## License

Apache-2.0, see [LICENSE.md](LICENSE.md).
