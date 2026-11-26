# docker-base-images-v3 — Plan

Status: accepted, phases 1–2 in progress · Date: 2026-11-26 · Replaces: `labor-digital/docker-base-images-v2`

## Implementation log

**2026-11-26:** the plan was accepted. Phases 1 (bootstrap) and 2 (PHP images) are implemented locally; nothing is pushed yet.

**Decisions applied with the recommended default** (§8), so any of them can still be changed in review:
- D1: GitHub + Actions + Docker Hub
- D2: new image name `docker-base-images-v3`
- D4: Node LTS lines only
- D5: v3.0 keeps root Apache master and ports 80/443
- D6: no baked certificate. The dev image trusts a CA mounted at `/var/cert/ca.crt`
- D9: Trivy blocks on regressions; until 3b exists, it blocks on any fixable CRITICAL

**D7 confirmed:** no local checkout under `~/Work/Labor` uses `ext-mcrypt`, `mcrypt_*()`, graphviz or `ext-xdebug`. So mcrypt, graphviz and the php82-dev xdebug are dropped.

**D3 not yet relevant:** boilerplates come in phase 5. **D8 decided:** code owner is the team `@labor-digital/developer` (5 members).

**Deviations from the plan text:**
- **`pr.yml` builds every target, not only the changed ones.** There are 8 parallel jobs with a per-target GHA cache, so unchanged targets are cache hits. That costs less than maintaining change-detection logic.
- **The `apachectl -t` check runs against the started container,** not the bare image. Without a baked certificate, the vhost only becomes valid once `bootstrap.sh` has generated one.
- **The Dockerfile has no default for `PHP_IMAGE`.** `docker-bake.hcl` is the only place a version is written. Otherwise Renovate would update two pins for one line.
- **No image `HEALTHCHECK` (§6 table).** Not every project serves `/test.php`, so a baked check would mark healthy containers as unhealthy. Health stays where it is today: in compose (boilerplate) and the ECS task definition.

---

## 0. What exists today (verified)

| Area | Finding | Where |
|---|---|---|
| Duplication | `php82`–`php85` are ~98 % identical. The real differences are the `FROM` line and the label. The rest is drift: `LogLevel info` vs `notice`, tabs vs spaces, xdebug only in `php82-dev`, a wrong tag comment in `php84/php84/Dockerfile:1-3` | `diff -r php84 php8x` |
| Duplication | 9 Node folders, 7 near-identical boilerplate copies, 12 near-identical workflows | `.github/workflows/*.yml` |
| Drift bug | The boilerplate `.env.template` uses `DOCKER_BASE_TAG=8.3.37` in php83 but `php-8.4.28` in php84 | `php83/boilerplate/.env.template:4` |
| Automation | PHP: Renovate handles patch and digest, with an amd64 PR check and automerge. Node: daily cron from floating tags (`node:22-bookworm-slim`), no pin, no PR check. A new PHP or Node line means copying a folder by hand | `renovate.json`, `node22.yml` |
| Workaround | 315 of 468 commits are "Heartbeat" commits. They only exist so GitHub doesn't disable the cron workflows. The same pattern is in `bitbucket-pipeline-images` and `docker-playwright` | `git log` |
| Repo security | No required review on `master`. The ruleset only requires the `pr-check` status, and the Admin role may bypass it. Secret scanning and push protection are off on a public repo. Actions are not pinned to a SHA (`sha_pinning_required: false`) | `gh api …/rulesets` |
| Image security | No vulnerability scan, no SBOM, no signature, `provenance: false`. Runs as root. `sudo`, `vim`, `nano` and `graphviz` ship in prod. Composer is installed by `curl \| php` with no checksum. Node uses the deprecated `apt-key`. The dummy TLS key is generated at build time with a hardcoded passphrase, so every pull gets the same key | `php84/php84/Dockerfile` |
| Image security | `pecl install mcrypt`: the extension is abandoned upstream | `php84/php84/Dockerfile:87` |
| EOL images | Docker Hub still serves node12/14/16/18/20 and php71/72/73/74/80. node12 and node14 were rebuilt on 2026-11-25 | Docker Hub tags |
| **Critical, outside the repo** | `labor-digital/ssl-certs` is **public** and contains the plain-text private key for `labor.systems` / `*.labor.systems` (valid until 2073). The `-dev` images bake in that cert. Every dev machine trusts `LABOR-digital-RootCA` (`CA:TRUE`, no name constraints, valid until 2071) | `gh api repos/labor-digital/ssl-certs/contents/labor.systems` |

### Consumers (what v3 must not break)

- **lab-cli** (`lab init`):
  - It runs `git clone` on the repo's default branch, then globs `**/lab.boilerplate.json` and needs a string `name` in it (`ProjectInitCommand.ts:127,135`).
  - It replaces placeholders in the files listed in `replaceProjectNameIn` (`§PROJECT_NAME§`, `§PROJECT_SHORT_NAME§`).
  - The repo URL is hardcoded in `DefaultConfig.ts:113`.
  - Compose: the main service key is `app`, and every service needs an explicit `container_name`.
  - `lab shell` uses `docker exec` without `-u`, so it opens as the image's USER.
- **Projects (Bitbucket)**:
  - Each project Dockerfile does `FROM ${DOCKER_BASE_IMAGE}:${DOCKER_BASE_TAG}` and compose uses `…-dev`. The values come from `.env.template`.
  - All 28 project templates under `~/Work/Labor` use **floating tags**: `node22` (20×), `php84` (7×), `php83` (1×). None pins a patch or digest. A fixed base image therefore reaches a project on its **next build**, not before.
  - CI turns every line of `.env.template` into a `--build-arg` (`bitbucket-pipeline-images/build-docker-and-push-ecr.sh:35-45`). The image is pushed to ECR and deployed to ECS.
- **Factory**: `apps/console/Dockerfile:15-16` uses `node22`, and the CI step image is `node22-dev` (`Factory/bitbucket-pipelines.yml:168`).
- **labor-prod-renovate** (Bitbucket):
  - The only base-image hook is the regex `DOCKER_BASE_TAG=php(\d)(\d)` (`src/bitbucket.config.js:37-49`). It does not match Node, `-dev` or patch tags.
  - Automerge is off.

### Company conventions that apply (from `Factory/CLAUDE.md`, git history, sibling repos)

- **Commits:** Conventional Commits. `feat` gives a minor version, `fix` a patch, and a major only by explicit decision.
- **Branches and merging:** prefixes `feature/` `bugfix/` `hotfix/` `renovate/`. `master` is PR-only. A merge needs a green build, a branch 0 commits behind master and no requested changes. Use merge commits, not squash.
- **Design logs** come before architecture changes, which is what this document is.
- **Language and licence:** code, comments, docs and commits are in English. Licence is Apache-2.0.
- **Env files:** `.env.template` has no comments, because CI word-splits it. `.env.app` holds secrets. Runtime secrets come from Doppler.
- **CI platform:** projects use Bitbucket Pipelines. The public image repos (v2, `bitbucket-pipeline-images`, `docker-playwright`) use GitHub Actions and push to Docker Hub, so v3 follows that precedent (see decision D1).

---

## 1. Goals and non-goals

**Goals:**
1. Each stack is defined in exactly one place. A new version is one line, not one copied folder.
2. New upstream versions (patch, digest and new minor lines) arrive as PRs on their own. Humans review and merge.
3. Every published image is scanned, has an SBOM and provenance, and is signed.
4. The repo cannot be changed without a human review.
5. Consumers can migrate mechanically: same tag scheme, same env vars, same compose conventions.

**Non-goals for v3.0** (named so they aren't forgotten):
- Moving `bitbucket-pipeline-images` and `docker-playwright` to the same build. They have the same heartbeat/cron problem, and v3 can become their template later.
- Image scanning in project pipelines. That belongs to `bitbucket-pipeline-images` and the projects, and is tracked separately.
- PHP 7.4 or any EOL Node. They stay frozen in v2 and are not carried into v3.

---

## 2. Repo layout (reduces duplication)

```
docker-base-images-v3/
├── docker-bake.hcl            # THE version matrix + all targets/tags (single source of truth)
├── images/
│   ├── php/
│   │   ├── Dockerfile         # one file, stages: base → dev   (ARG PHP_VERSION)
│   │   ├── extensions.txt     # one list of PHP extensions, used by build AND smoke test
│   │   └── rootfs/            # conf/ + opt/ copied verbatim (apache, php.ini, bootstrap.sh …)
│   └── node/
│       ├── Dockerfile         # stages: base → dev   (ARG NODE_VERSION)
│       └── rootfs/
├── shared/rootfs/             # .bashrc helpers (ensure_dir, ensure_perms …), readEnv.sh, locale preseed
├── boilerplates/
│   ├── php/                   # lab.boilerplate.json  name: "PHP"
│   ├── php-no-mysql/
│   └── node/
├── tests/
│   ├── smoke.sh               # runs inside each built image (see §5)
│   └── boilerplate/           # existing playwright test, reused
├── scripts/new-versions.sh    # the "new PHP/Node line" detector (§4.2)
├── .github/
│   ├── workflows/{pr.yml,release.yml,new-versions.yml,renovate.yml,rescan.yml}
│   └── CODEOWNERS
├── renovate.json
└── .design-log/001-v3-architecture.md   # this file
```

How this removes the duplication:
- **One Dockerfile per stack** with `ARG PHP_VERSION`/`NODE_VERSION`. `base` and `dev` are stages in the same file, built with `--target`. The dev image can no longer drift from its base (today `pr-check` exists only to catch that).
- **Shared files** come in through a bake named context (`contexts = { shared = "shared/rootfs" }`, then `COPY --from=shared`), so the bash helpers exist once for PHP and Node.
- **The matrix lives in `docker-bake.hcl`:**
  ```hcl
  variable "PHP" { default = {
    "8.2" = "8.2.36-apache@sha256:832428a7…",
    "8.3" = "8.3.37-apache@sha256:fb5e4498…",
    "8.4" = "8.4.28-apache@sha256:95c1a1df…",
    "8.5" = "8.5.13-apache@sha256:256c2514…",
  }}
  target "php" {
    matrix = { minor = keys(PHP), stage = ["base", "dev"] }
    …tags computed from minor/stage
  }
  ```
  Renovate updates these strings with a regex manager. CI, local builds and smoke tests all read the same file.
- **PHP extensions** install through `mlocati/docker-php-extension-installer`, pulled in with `COPY --from=…@sha256`. It already handles per-version differences (for example opcache being built into 8.5), so the per-version `if`s and folder copies go away. `extensions.txt` is the single list for building and for the test assertion.
- **One workflow per job instead of one per version:** `docker buildx bake --print` produces the matrix, so 12 workflows become 3.
- **Boilerplates go from 7 copies to 3.** The PHP version is `DOCKER_BASE_TAG` in `.env.template` and defaults to the newest supported line (see decision D3).

---

## 3. Tags (compatible with v2, so migration is a find-and-replace)

Image: `labordigital/docker-base-images-v3` on Docker Hub (decision D2).

| Tag | Meaning | Moves? |
|---|---|---|
| `php8.4` / `php8.4-dev` | latest patch of the line | yes |
| `php84` / `php84-dev` | v2-style alias, so labor-prod-renovate's regex keeps working | yes |
| `php-8.4.28` / `php-8.4.28-dev` | exact upstream patch | **no**: written once, never overwritten |
| `node22` / `node22-dev` | latest of the line | yes |
| `node-22.x.y` / `node-22.x.y-dev` | exact upstream version | no |

Projects keep using the floating `php84` / `node22` tags, as all of them do today. Each one changes only `DOCKER_BASE_IMAGE` to migrate. The immutable `php-X.Y.Z` tags exist for rollback and for anyone who wants to pin.

---

## 4. Automation

### 4.1 Upstream updates: two lanes (Renovate, GitHub-hosted, reuses the existing v2 setup)

**Requirement:** when a security fix ships upstream (a PHP or Node patch release, or a Debian package fix that rebuilds the official image), our images must update **without waiting for a human**. Everything else stays human-reviewed.

- **Kept from v2:** the GitHub App token, `platformCommit`, a pinned `renovate-version`, and Docker Hub auth for lookups. Renovate keeps running every hour.
- **What Renovate tracks:**
  - `php:*-apache` and `node:*-bookworm-slim` inside `docker-bake.hcl` (regex manager, `pinDigests`)
  - `mlocati/php-extension-installer`, `composer`, the Doppler CLI version, and GitHub Actions (`helpers:pinGitHubActionDigests`)
- **Major and minor updates are disabled for the base images,** because a line is fixed and new lines come from §4.2.

| Lane | What | Who merges |
|---|---|---|
| **Auto** | Upstream **patch or digest** of `php` / `node` official images, and nothing else in the diff (e.g. `8.4.28` → `8.4.29`, or a new digest of `8.4.28`) | Renovate, as soon as every required check is green. No human approval |
| **Review** | Everything else: extension installer, composer, Doppler, Actions, new lines (§4.2), any human change | A human (CODEOWNER approval), as in §6 |

**How the auto lane stays safe without a human:**
1. **The guard check (`renovate-guard`):** a required check that runs on `pull_request_target`. That means the workflow file comes from `master`, so a PR cannot edit its own guard. It reads the diff through the API and never checks out or executes PR code. For a PR from the Renovate App it passes only if:
   - the only changed file is `docker-bake.hcl`
   - every changed line is a version/digest string of an existing line, with the same minor (`8.4.x` stays `8.4.x`)
   - the new digest is exactly what `docker buildx imagetools inspect docker.io/library/php:<new tag>` (or `node:`) returns right now
   
   If any condition fails, the guard requires an approving CODEOWNER review instead (it re-runs on `pull_request_review`). PRs from humans always need that approval anyway.
2. **The same tests as any PR:** build, smoke tests, the boilerplate playwright test, and Trivy. For the auto lane Trivy blocks on **regressions**: a fixable CRITICAL that the currently published tag doesn't already have. Otherwise one old upstream CVE without a fix would block every security update behind it. Findings that are already known go into the weekly `rescan.yml` issue (§4.3).
3. **Rulesets split so the bot only skips the review, never the checks** (§6). One ruleset holds the required checks (including `renovate-guard`) and has no bypass for anyone. The other holds the review requirement, and only the Renovate App may bypass it, in `pull_request` mode. Even a stolen App key can therefore only merge a pure, verified upstream digest bump.
4. **Merging:** Renovate merges the PR itself (`automerge: true`, `platformAutomerge: false`). It waits until all checks are green, then merges through its ruleset bypass.
5. **After-the-fact review:** every auto-merged release posts what changed (old→new version and digest, Trivy delta) to a pinned GitHub issue, which can also go to Slack. A human skims it weekly. Rollback means re-pointing the moving tag to the previous immutable `php-X.Y.Z` tag (documented one-liner in the README).

**Expected time from upstream release to our image:**
- The official image publishes a few hours after php.net or nodejs.org.
- Renovate picks it up within an hour.
- Checks take about 20 minutes, and release builds about 20 minutes (native arm64).
- So the fix is out the **same day**, with no human in the loop.

**The last link: projects.** All projects use floating tags (§0), so they get the fix on their next Bitbucket build. A project that doesn't deploy stays on the old base. See decision D10.

### 4.2 New PHP or Node lines (new: scheduled workflow, weekly)
`scripts/new-versions.sh`:
1. Reads `https://endoflife.date/api/php.json` and `/nodejs.json`, which give each release line, its EOL date and its latest version.
2. For Node, keeps only LTS lines (decision D4).
3. **Adds a line** when it is GA, not EOL, missing from `docker-bake.hcl`, and the official image `php:<X.Y.Z>-apache` already exists (checked with `docker buildx imagetools inspect`). It writes the entry with its digest.
4. **Marks a line as EOL** in the PR description when its EOL date is less than 90 days away. Past EOL it moves the line to the `frozen` list: still published, no longer rebuilt, labelled `org.labor.eol=true`.
5. Opens a PR through the same GitHub App, with the title `feat(php): add PHP 8.6`. **It never pushes to master.** The PR runs the full test set (§5), including the boilerplate test against the new line.

Its own check: `scripts/new-versions.sh --self-test` runs against a fixture JSON and asserts the add, EOL and no-op cases. It runs in `pr.yml`.

### 4.3 Rebuilds without heartbeat commits
- Official `php`/`node` images rebuild whenever Debian publishes fixes, which changes their digest. Renovate's digest PR therefore already triggers our rebuild, so no daily cron rebuild is needed.
- Without the cron, the heartbeat commits are no longer needed and get deleted.
- The Renovate cron stays active because Renovate's own commits count as repo activity.
- `rescan.yml` (weekly) runs Trivy against the **published** tags and opens or updates a GitHub issue when a new CRITICAL appears. That covers CVEs found after a build.

---

## 5. Build, test and publish pipeline

**`pr.yml`** (required check, no push, no secrets for fork PRs):
1. `hadolint` on both Dockerfiles, `shellcheck` on `rootfs/**/*.sh` and `scripts/*.sh`, `actionlint` on the workflows.
2. `docker buildx bake --print` to validate the matrix.
3. **Builds only the targets that changed**, for linux/amd64. If `shared/` or a Dockerfile changed, all lines of that stack rebuild.
4. `tests/smoke.sh` inside each image:
   - `php -m` must match `extensions.txt`; `apachectl -t` must pass
   - the container starts and `/test.php` returns 200
   - `id -u` is as expected (D5)
   - `doppler --version`; and `composer --version` for dev only
5. **Trivy** on each built image. It fails on a CRITICAL with a fix available that the currently published tag does not already have, and reports HIGH. A new line (no published tag yet) fails on any fixable CRITICAL.
6. **Boilerplate test** for the newest PHP line: `docker compose up` with the existing playwright test (`boilerplates/php/tests`).

**`release.yml`** (on merge to master):
- **Build:** native runners per architecture (`ubuntu-latest` and `ubuntu-24.04-arm`), push by digest, then merge the manifest lists. This is the v2 PHP pattern and it already works.
- **Supply chain:** `provenance: mode=max` and `sbom: true` (BuildKit attestations), plus `cosign sign` keyless via GitHub OIDC.
- **Tags:** immutable patch tags are only written if they don't exist yet; moving tags are written afterwards.
- **Permissions:** `permissions: contents: read, id-token: write` at job level, nothing else.

**Dev certificates:** the `-dev` stage **does not bake in any certificate**. `bootstrap.sh` uses `/var/cert/merged.crt` if it is mounted. Otherwise it generates a self-signed cert on first start, unique per container, with no shared key. The boilerplate compose mounts the developer's cert (D6).

---

## 6. Security

**Repo (GitHub settings):**
- **Two rulesets on `master`** (see §4.1 for why they are split):
  - **`master-checks`:** required checks `pr` and `renovate-guard`, branch must be up to date, no force push or deletion. **No bypass actors**, not even admins.
  - **`master-review`:** PR required, **1 approval**, CODEOWNERS review for `.github/**`, `images/**/Dockerfile`, `docker-bake.hcl`, `renovate.json` and `scripts/**`, review dismissed on new pushes. The **only** bypass actor is the Renovate GitHub App, in `pull_request` mode.
- **Scanning:** secret scanning + push protection on. Dependabot alerts on (alerts only; Renovate opens the PRs).
- **Actions:**
  - only allow `selected` actions (GitHub-owned, docker/*, sigstore/*, aquasecurity/*, renovatebot/*)
  - `sha_pinning_required: true`
  - default `GITHUB_TOKEN` permissions read-only
- **Org Docker Hub token:** one scoped access token (read/write for this one repo), stored as an environment secret on a `release` environment that only `master` can use.

**Image:**

| v2 | v3 |
|---|---|
| `sudo vim nano graphviz` in prod | only in `-dev` |
| composer via `curl \| php` | `COPY --from=composer:2@sha256:…` (dev only) |
| Doppler via `apt-key` (Node) | `signed-by` keyring, same as PHP; version pinned, Renovate-tracked |
| dummy TLS key baked at build, hardcoded passphrase | generated at first start |
| `MAINTAINER` (deprecated) | OCI labels: source, revision, version, licenses |
| `pecl mcrypt` | dropped (D7) |
| apt lists left in layers | `rm -rf /var/lib/apt/lists/*`, `--no-install-recommends` |
| root at runtime | see D5 |
| no healthcheck | `HEALTHCHECK` on `/test.php`-equivalent |

**Outside this repo, urgent and independent of v3:** the `*.labor.systems` key in the public `ssl-certs` repo.
1. Generate a new leaf key.
2. Remove the key files from the repo, and from its history and the npm package `@labor-digital/ssl-certs`.
3. Ideally replace the root CA with one that has `nameConstraints` (`labor.systems`, `localhost`, `localmachine.space`), or switch to `mkcert` per developer (D6).

Until then, anyone can use that key to impersonate `*.labor.systems` to every LABOR dev machine. The apex `labor.systems` resolves publicly.

---

## 7. Phases (each one is a separate PR, small enough to review by hand)

| # | PR | Done when |
|---|---|---|
| 0 | **ssl-certs:** rotate the leaf key, remove the keys (separate repo, separate owner) | the old key is no longer in any published artifact |
| 1 | Repo bootstrap: LICENSE (Apache-2.0), README, ruleset, CODEOWNERS, `pr.yml` with lint only, `renovate.json`, this design log | the ruleset blocks a direct push in a test |
| 2 | `images/php` + `shared/` + bake matrix + smoke tests + Trivy, **no publishing** | all 4 PHP lines × base/dev green in PR. A diff of `php -m` and `apachectl -M` against the v2 images shows only the intended changes |
| 3 | `release.yml`: signing, SBOM, immutable tags | `cosign verify` and `docker buildx imagetools inspect --format '{{json .SBOM}}'` pass on a published tag |
| 3b | **Auto lane:** `renovate-guard` (`pull_request_target`, API-only), the two rulesets, Renovate automerge rules, auto-release issue | The guard's self-test (diff fixtures) passes all four cases: pure digest bump → pass; minor bump → needs review; a second file touched → needs review; digest that doesn't match the registry → needs review. A real Renovate digest PR then merges and releases with no human, and a PR that edits the guard can't skip it |
| 4 | `images/node` (only lines that aren't EOL) | same as 2 |
| 5 | Boilerplates (3) + boilerplate test. lab-cli: new default URL + release; fix the broken `uses: u@master` on lab-cli `dev` first | `lab init --boilerplate "PHP"` works against v3 |
| 6 | `new-versions.yml` + self-test | dry run against fixtures. A real run produces no PR (everything up to date) |
| 7 | `rescan.yml` | an issue is created for a deliberately old test tag |
| 8 | Migration: labor-prod-renovate regex; switch one pilot project (`DOCKER_BASE_IMAGE` in `.env.template`), deploy to staging, then the rest | the pilot runs on ECS staging |
| 9 | v2: README deprecation notice, stop the cron and heartbeat, archive once no project pulls it | Docker Hub pull count is about 0 |

**Review rule for every phase:**
- 1 human approval, from a CODEOWNER for infrastructure files.
- The reviewer pulls the image from the PR's build and runs the smoke test locally on arm64 (Mac), since CI only builds amd64 in PRs.

---

## 8. Open decisions (need an answer before phase 1)

| # | Question | Recommendation |
|---|---|---|
| D1 | Where does v3 live and build? | GitHub + Actions + Docker Hub, the same as v2, `bitbucket-pipeline-images` and `docker-playwright`. lab-cli needs a public unauthenticated clone, and projects pull from Docker Hub |
| D2 | New image name `…-v3`, or keep `…-v2` with new tags? | **New name.** v2 projects keep working untouched, and migration is opt-in per project |
| D3 | Boilerplates: one per stack (`"PHP"`), or keep per-version names (`"PHP 8.4"`)? | **One per stack.** This breaks scripted `lab init --boilerplate "PHP 8.4"` calls. Check whether anyone scripts that |
| D4 | Node: LTS lines only? | Yes |
| D5 | Non-root runtime: prod Apache as `www-data` on 8080/8443? | **Phase it.** v3.0 keeps today's model (root Apache master, `www-data` workers, ports 80/443) so migration is just a tag change. v3.1 goes non-root, together with updating the ECS task definitions and moving the `chown` at boot from `bootstrap.sh` to build time or EFS access points. Doing both in one step makes every project migration a port and permission change |
| D6 | Dev TLS: new name-constrained LABOR CA (private, not in a public repo), or `mkcert` per developer? | `mkcert` per developer via `lab install-ca` (lab-cli change). No shared key exists anywhere |
| D7 | Drop `mcrypt` and `graphviz`? | Yes, unless a project needs them. Grep the projects' composer.json for `ext-mcrypt` before phase 2 |
| D8 | Who are the CODEOWNERS (at least 2 people)? | Team `@labor-digital/developer` |
| D9 | Trivy gate: block on any fixable CRITICAL, or only on a regression against the published tag? | **Regression**, for both PRs and releases (§4.1). Otherwise one old upstream CVE blocks the security updates behind it. A documented `.trivyignore` entry (reason + expiry date) is the only bypass |
| D10 | Should projects be rebuilt automatically when the base image gets a security update? Today a fix only reaches a project on its next deploy | Start with a weekly Bitbucket **scheduled pipeline** per project (build and deploy to staging), plus a Slack ping listing the projects whose production image is older than the newest base. Auto-deploying production is a separate decision per project |

---

## 9. Not verified yet
- The shared Bitbucket repo `labor-dev-pipelines`, because it isn't cloned locally.
- `TyAs/*`.
- Whether any project uses `mcrypt`, `graphviz`, xdebug from `php82-dev`, or PHP 7.4 in production.
- How ECS terminates TLS. If the ALB terminates it, the prod image may not need 443 at all (simplifies D5).
