#!/usr/bin/env bash
if [ "$EUID" -eq 0 ]; then
  echo "root"
else
  echo "not root"
fi
