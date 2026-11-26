#!/bin/bash

# Load global aliases
source /root/.bashrc

# Read environment if possible
source /opt/readEnv.sh

# Initialize volume directory permissions
ensure_perms /var/www/html_data
ensure_perms /var/www/logs

# Make sure apache webroot exists
ensure_dir "$APACHE_WEBROOT"

# No key ships in the image: unless a certificate is mounted, generate one per container
if [ ! -f /var/cert/merged.crt ]; then
  echo "No certificate mounted at /var/cert/merged.crt, generating a self-signed one"
  (
    umask 077
    openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=localhost" \
      -keyout /tmp/server.key -out /tmp/server.crt 2>/dev/null
    cat /tmp/server.crt /tmp/server.key > /var/cert/merged.crt
    rm -f /tmp/server.key /tmp/server.crt
  ) || { echo "Could not generate a self-signed certificate" >&2; exit 1; }
fi

# Used as a hook to run the bootstrap script of our dev container
if [ -f "/opt/dev/bootstrap.sh" ]; then
  source /opt/dev/bootstrap.sh
fi

# Run project specific bootstrap if required
if [ -f "/opt/project/bootstrap.sh" ]; then
  source /opt/project/bootstrap.sh
fi

# Set the correct permissions for the files
set_permissions

# Run the main process
exec apache2-foreground
