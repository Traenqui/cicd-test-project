#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

FILES=(schemas/events/*.json)
((${#FILES[@]}==0)) && { echo "No schemas/events/*.json found, skipping."; exit 0; }

fail=0
for f in "${FILES[@]}"; do
  # allow schema-level exemptions if needed
  exempt="$(jq -r '(.["x-policy-exempt"] // []) | join(",")' "$f")"

  jq -e '
    (.type == "object")
    and ((.required // []) | index("eventId") != null)
    and ((.required // []) | index("eventType") != null)
    and ((.required // []) | index("occurredAt") != null)
    and ((.required // []) | index("payload") != null)
    and (.properties.eventId.type == "string")
    and ((.properties.eventId.format? // "") == "uuid" or (.properties.eventId.pattern? // "") != "")
    and (.properties.occurredAt.type == "string")
    and ((.properties.occurredAt.format? // "") == "date-time")
  ' "$f" >/dev/null || { echo "❌ [EVENT ENVELOPE] $f missing required envelope fields"; fail=1; }

  # Enforce correlationId unless exempted
  if [[ "$exempt" != *"require-correlationId"* ]]; then
    jq -e '
      ((.required // []) | index("correlationId") != null)
      and (.properties.correlationId.type == "string")
    ' "$f" >/dev/null || { echo "❌ [EVENT ENVELOPE] $f correlationId required (or add x-policy-exempt: [\"require-correlationId\"])"; fail=1; }
  fi
done

exit $fail

