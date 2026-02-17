#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

SPECS=(asyncapi/*.yaml asyncapi/*.yml asyncapi/*.json)

to_json() {
  local f="$1"
  if [[ "$f" == *.json ]]; then
    cat "$f"
  else
    command -v yq >/dev/null 2>&1 || { echo "yq not found (needed for YAML)"; exit 2; }
    yq -o=json '.' "$f"
  fi
}

fail=0
check() {
  local name="$1" file="$2" filter="$3"
  local out
  out="$(to_json "$file" | jq -r "$filter" 2>/dev/null || true)"
  if [[ -n "${out// }" ]]; then
    echo "❌ $name — $file"
    echo "$out"
    echo
    fail=1
  fi
}

for spec in "${SPECS[@]}"; do
  check "AsyncAPI must have info.title and info.version (semver)" "$spec" '
    def semver: "^[0-9]+\\.[0-9]+\\.[0-9]+(-[0-9A-Za-z.-]+)?$";
    if ((.info.title // "") == "" or ((.info.version // "") | test(semver) | not))
    then "  missing info.title or invalid info.version (expected semver x.y.z)"
    else empty end
  '

  check "Channel names must be lowercase (recommended pattern)" "$spec" '
    (.channels // {}) | keys[]
    | select( test("^[a-z0-9]+([._-][a-z0-9]+)*(\.v[0-9]+)?$") | not )
    | "  channel: \(.)"
  '

  check "Each channel must have publish or subscribe" "$spec" '
    (.channels // {}) | to_entries[]
    | select((.value.publish? == null) and (.value.subscribe? == null))
    | "  channel: \(.key)"
  '

  check "OperationId must exist for each publish/subscribe" "$spec" '
    (.channels // {}) | to_entries[] as $c
    | (["publish","subscribe"][]?) as $dir
    | ($c.value[$dir]? // empty) as $op
    | select($op != null)
    | select((($op.operationId // "") == ""))
    | "  \($dir|ascii_upcase) \($c.key): missing operationId"
  '

  check "OperationId must be unique" "$spec" '
    def ops:
      (.channels // {}) | to_entries[] as $c
      | (["publish","subscribe"][]?) as $dir
      | ($c.value[$dir]? // empty) as $op
      | select($op != null)
      | {channel:$c.key, dir:$dir, operationId:($op.operationId // "")};

    [ops | select(.operationId != "")] as $all
    | ($all | group_by(.operationId) | map(select(length>1)))[]?
    | "  operationId: \([.[0].operationId]) used by: " +
      (map("\(.dir|ascii_upcase) \(.channel)") | join(", "))
  '

  check "Each operation must define a message with name + payload" "$spec" '
    (.channels // {}) | to_entries[] as $c
    | (["publish","subscribe"][]?) as $dir
    | ($c.value[$dir]? // empty) as $op
    | select($op != null)
    | ($op.message? // empty) as $m
    | select($m == null or ($m.name? // "") == "" or ($m.payload? == null))
    | "  \($dir|ascii_upcase) \($c.key): message must have name and payload"
  '

  check "defaultContentType or message.contentType must be set" "$spec" '
    def has_ct($m): (($m.contentType? // "") != "");
    def spec_ct: ((.defaultContentType? // "") != "");
    (.channels // {}) | to_entries[] as $c
    | (["publish","subscribe"][]?) as $dir
    | ($c.value[$dir]? // empty) as $op
    | select($op != null)
    | ($op.message? // empty) as $m
    | select($m != null)
    | select((spec_ct or has_ct($m)) | not)
    | "  \($dir|ascii_upcase) \($c.key): missing defaultContentType and message.contentType"
  '

  # Require an "idempotency / identity" mechanism:
  # - either message.messageId is set
  # - OR payload is a $ref into schemas/events (assumed envelope has eventId)
  check "Message should have messageId or payload $ref to schemas/events/..." "$spec" '
    (.channels // {}) | to_entries[] as $c
    | (["publish","subscribe"][]?) as $dir
    | ($c.value[$dir]? // empty) as $op
    | select($op != null)
    | ($op.message? // empty) as $m
    | select($m != null)
    | ($m.messageId? // "") as $mid
    | ($m.payload? // {}) as $pl
    | select(
        ($mid == "")
        and
        ( ($pl["$ref"]? // "") | test("schemas/events/") | not )
      )
    | "  \($dir|ascii_upcase) \($c.key): missing messageId and payload $ref does not point to schemas/events/"
  '

  # Correlation requirement:
  # - either message.correlationId exists
  # - OR headers exists (inline or $ref). If headers are inline, require correlationId property.
  check "Message should define correlationId or headers correlationId" "$spec" '
    (.channels // {}) | to_entries[] as $c
    | (["publish","subscribe"][]?) as $dir
    | ($c.value[$dir]? // empty) as $op
    | select($op != null)
    | ($op.message? // empty) as $m
    | select($m != null)
    | ($m.correlationId? != null) as $hasCorr
    | ($m.headers? // null) as $hdr
    | ($hdr["$ref"]? != null) as $hdrRef
    | ($hdr.properties.correlationId? != null) as $hdrInlineCorr
    | select( ($hasCorr or $hdrRef or $hdrInlineCorr) | not )
    | "  \($dir|ascii_upcase) \($c.key): missing correlationId (message.correlationId or headers.correlationId/$ref)"
  '
done

exit $fail

