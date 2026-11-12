#!/bin/bash
# The plain 6128 version's regression tests: tools/cpc512/test.sh with
# VARIANT=cpc6128.
VARIANT=cpc6128 exec "$(dirname "$0")/../cpc512/test.sh" "$@"
