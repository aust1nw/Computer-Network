#!/usr/bin/env bash
set -e

export TINYOS_ROOT_DIR="${TINYOS_ROOT_DIR:-/usr/share/tinyos}"
export TOSROOT="${TOSROOT:-$TINYOS_ROOT_DIR}"
export TOSDIR="${TOSDIR:-$TOSROOT/tos}"
export CLASSPATH="${CLASSPATH:-/usr/share/java/tinyos.jar:.}"
export MAKERULES="${MAKERULES:-$TOSROOT/Makefile.include}"
export PYTHONPATH="${PYTHONPATH:-/usr/lib/python2.7/dist-packages:$TOSROOT/support/sdk/python:/workspace}"

cd /workspace
exec "$@"
