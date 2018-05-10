#!/bin/bash
set -e

SCRIPT_DIR=$(dirname $0)
ADDED_DIR=${SCRIPT_DIR}/added

# includes misc modules aliases etc for compatiilty
# Remove any existing destination files first (which might be symlinks)
cp -rp --remove-destination "$ADDED_DIR/modules" "$JBOSS_HOME/"

chown -R jboss:root $JBOSS_HOME
chmod -R g+rwX $JBOSS_HOME
