#!/bin/bash
set -u
xwd -help 2>&1 || true
man xwd 2>/dev/null | col -b | sed -n '1,180p' || true
