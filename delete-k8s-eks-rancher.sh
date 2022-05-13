#!/usr/bin/env bash

set -euo pipefail

sed -n "/^\`\`\`bash.*/,/^\`\`\`$/p" docs/src/part-cleanup.md | sed "/^\`\`\`*/d" | bash -euxo pipefail
