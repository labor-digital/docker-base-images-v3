# The single source of truth for which image lines exist and what they are built from.
#
# One row per line: { minor, image, tag, digest } on ONE line. Renovate (auto lane) rewrites tag + digest,
# renovate-guard and scripts/new-versions.sh parse the same rows. Keep that format.
#
#   docker buildx bake --print            # show everything that would be built
#   docker buildx bake php84-base --load  # build one target locally
#   docker buildx bake                    # build everything

variable "IMAGE" {
  default = "labordigital/docker-base-images-v3"
}

group "default" {
  targets = ["php"]
}

target "php" {
  name = "php${replace(v.minor, ".", "")}-${stage}"
  matrix = {
    v = [
      { minor = "8.2", image = "php", tag = "8.2.36-apache", digest = "sha256:832428a7cc89ea5c54e8b23e041809e1fe0e14cfcd605b287505d0bd721b658c" },
      { minor = "8.3", image = "php", tag = "8.3.37-apache", digest = "sha256:fb5e44981a84757b95cd29440f534509f42a9766382c8c83bfd404924a62379b" },
      { minor = "8.4", image = "php", tag = "8.4.28-apache", digest = "sha256:95c1a1dfaaffef4bcfee563838c50620457a3c00196c4bf5ddb66934d707fea2" },
      { minor = "8.5", image = "php", tag = "8.5.13-apache", digest = "sha256:256c25149bca6639f538ece3c5dda90684409227dec546b87ca174950569b8f1" },
    ]
    stage = ["base", "dev"]
  }
  context  = "images/php"
  contexts = { shared = "shared/rootfs" }
  target   = stage
  args     = { PHP_IMAGE = "${v.image}:${v.tag}@${v.digest}" }
  labels   = { "org.opencontainers.image.version" = trimsuffix(v.tag, "-apache") }
  # php8.4 / php84 move with every patch, php-8.4.28 never changes once published (see .design-log/001 §3)
  tags = [
    for t in ["php${v.minor}", "php${replace(v.minor, ".", "")}", "php-${trimsuffix(v.tag, "-apache")}"] :
    "${IMAGE}:${t}${stage == "dev" ? "-dev" : ""}"
  ]
}
