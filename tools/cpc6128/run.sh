#!/bin/bash
# The plain 6128 version in MAME: tools/cpc512/run.sh with VARIANT=cpc6128.
VARIANT=cpc6128 exec "$(dirname "$0")/../cpc512/run.sh" "$@"
