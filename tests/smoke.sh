#!/usr/bin/env bash
# Smoke test for one built PHP image. Runs in CI for every target and locally before review.
#
#   tests/smoke.sh <image-ref> <base|dev> <expected-php-version>
#   tests/smoke.sh labordigital/docker-base-images-v3:php-8.4.28 base 8.4.28
set -euo pipefail

IMAGE="${1:?image ref}"
STAGE="${2:?base|dev}"
EXPECTED_VERSION="${3:?expected php version, e.g. 8.4.28}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FAILURES=0

pass() { echo "  ok    $1"; }
fail() { echo "  FAIL  $1" >&2; FAILURES=$((FAILURES + 1)); }
check() { local name="$1"; shift; if "$@" > /dev/null 2>&1; then pass "$name"; else fail "$name"; fi; }
in_image() { docker run --rm --entrypoint bash "$IMAGE" -c "$1"; }

echo "Smoke test: $IMAGE ($STAGE, expecting PHP $EXPECTED_VERSION)"

# --- static checks -------------------------------------------------------------
actual_version="$(in_image 'php -r "echo PHP_VERSION;"')"
[ "$actual_version" = "$EXPECTED_VERSION" ] && pass "php version $actual_version" || fail "php version is $actual_version"

loaded="$(in_image 'php -r "echo strtolower(implode(PHP_EOL, array_merge(get_loaded_extensions(), get_loaded_extensions(true))));"')"
loaded="${loaded//zend opcache/opcache}"
# extensions.txt is what we install; the rest ship with the official image and projects rely on them
for ext in $(grep -vE '^\s*(#|$)' "$REPO_ROOT/images/php/extensions.txt") curl mbstring fileinfo iconv openssl sodium; do
  grep -qx "$ext" <<< "$loaded" && pass "extension $ext" || fail "extension $ext not loaded"
done

for feature in "JPEG Support" "WebP Support" "FreeType Support"; do
  check "gd $feature" in_image "php -r 'exit(gd_info()[\"$feature\"] ? 0 : 1);'"
done

check "doppler cli present" in_image 'doppler --version'
check "timezone Europe/Berlin" in_image '[ "$(cat /etc/timezone)" = Europe/Berlin ] && [ "$(readlink -f /etc/localtime)" = /usr/share/zoneinfo/Europe/Berlin ]'
check "locales en_US + de_DE" in_image 'locale -a | grep -qx en_US.utf8 && locale -a | grep -qx de_DE.utf8'
check "no TLS key baked into the image" in_image '[ ! -e /var/cert/merged.crt ]'

if [ "$STAGE" = "dev" ]; then
  check "composer works" in_image '/usr/local/bin/composer.phar --version'
  check "composer wrapper defined" in_image 'source /root/.bashrc && declare -F composer'
  check "dev tools (sudo git mysql)" in_image 'command -v sudo && command -v git && command -v mysql'
  check "dev php.ini (display_errors=On)" in_image '[ "$(php -r "echo ini_get(\"display_errors\");")" = 1 ]'
else
  check "no sudo/vim/nano in production image" in_image '! command -v sudo && ! command -v vim && ! command -v nano'
  check "display_errors off" in_image '[ -z "$(php -r "echo ini_get(\"display_errors\");")" ]'
fi

# --- runtime: boot it like production (without doppler) and serve a request ----
container="smoke-$$"
trap 'docker rm -f "$container" > /dev/null 2>&1 || true' EXIT
docker run -d --name "$container" "$IMAGE" /opt/bootstrap.sh > /dev/null
docker exec "$container" bash -c 'echo "<?php echo \"smoke-ok\";" > /var/www/html/test.php'

up=""
for _ in $(seq 1 30); do
  if docker exec "$container" curl -fsS http://localhost/test.php 2> /dev/null | grep -q smoke-ok; then up=1; break; fi
  sleep 1
done
if [ -n "$up" ]; then pass "http serves php"; else fail "http serves php"; docker logs "$container" >&2 || true; fi
# Only valid at runtime: the vhost needs /var/cert/merged.crt, which bootstrap generates (nothing is baked in)
check "apache config valid (apachectl -t)" docker exec "$container" apachectl -t
check "https serves php (self-signed)" docker exec "$container" bash -c 'curl -fsSk https://localhost/test.php | grep -q smoke-ok'
check "generated cert is private (600)" docker exec "$container" bash -c '[ "$(stat -c %a /var/cert/merged.crt)" = 600 ]'
check "apache workers run as www-data" docker exec "$container" bash -c 'for p in /proc/[0-9]*; do [ "$(cat "$p/comm" 2>/dev/null)" = apache2 ] && stat -c %U "$p"; done | grep -qx www-data'

if [ "$FAILURES" -gt 0 ]; then
  echo "$FAILURES check(s) failed for $IMAGE" >&2
  exit 1
fi
echo "All checks passed for $IMAGE"
