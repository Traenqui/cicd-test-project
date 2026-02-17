#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

# Where your OpenAPI specs live (adjust as needed)
SPECS=(openapi/*.yaml openapi/*.yml openapi/*.json)

if ((${#SPECS[@]} == 0)); then
  echo "No OpenAPI specs found under openapi/"; exit 0
fi

# Convert YAML->JSON (yq required) or pass JSON through.
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

run_check() {
  local name="$1" file="$2" jq_filter="$3"
  local out
  out="$(to_json "$file" | jq -r "$jq_filter" 2>/dev/null || true)"
  if [[ -n "${out// }" ]]; then
    echo "❌ $name — $file"
    echo "$out"
    echo
    fail=1
  fi
}

for spec in "${SPECS[@]}"; do
  # --- Path naming rules ---
  run_check "Paths must be lowercase" "$spec" '
    (.paths // {}) | keys[]
    | select(test("[A-Z]"))
    | "  path: \(. )"
  '

  run_check "No trailing slash (except /)" "$spec" '
    (.paths // {}) | keys[]
    | select(. != "/" and test("/$"))
    | "  path: \(. )"
  '

  # Avoid verbs in path segments (opinionated baseline; tweak regex to your liking)
  run_check "Paths should avoid verb-like segments" "$spec" '
    def is_param: test("^\\{.*\\}$");
    def verb_re: "^(get|set|create|update|delete|list|search|add|remove|make|do|run|execute|login|logout)$";
    (.paths // {}) | keys[] as $p
    | ($p | split("/") | map(select(length>0)) | map(select(is_param|not))) as $segs
    | select(any($segs[]; test(verb_re; "i")))
    | "  path: \($p)  (segments: \($segs|join(",")))"
  '

  # --- Operation hygiene rules ---
  run_check "Only standard HTTP methods are allowed under paths" "$spec" '
    def allowed: ["get","post","put","patch","delete","head","options","trace"];
    (.paths // {}) | to_entries[]
    | .key as $p
    | (.value // {}) | to_entries[]
    | select(.key|ascii_downcase != .key or (allowed|index(.key))==null)
    | "  path: \($p)  invalidMethodKey: \(.key)"
  '

  run_check "GET must not define requestBody" "$spec" '
    (.paths // {}) | to_entries[]
    | .key as $p
    | (.value.get? // empty)
    | select(has("requestBody"))
    | "  GET \($p): has requestBody"
  '

  run_check "POST should return 201 or 202" "$spec" '
    (.paths // {}) | to_entries[]
    | .key as $p
    | (.value.post? // empty) as $op
    | ($op.responses // {}) | keys as $codes
    | select(($codes|index("201"))==null and ($codes|index("202"))==null)
    | "  POST \($p): missing 201/202 response"
  '

  run_check "DELETE should return 204 or 202" "$spec" '
    (.paths // {}) | to_entries[]
    | .key as $p
    | (.value.delete? // empty) as $op
    | ($op.responses // {}) | keys as $codes
    | select(($codes|index("204"))==null and ($codes|index("202"))==null)
    | "  DELETE \($p): missing 204/202 response"
  '

  run_check "Every operation must define at least one 4xx and one 5xx response" "$spec" '
    def ops:
      (.paths // {}) | to_entries[]
      | .key as $p
      | (.value // {}) | to_entries[]
      | select(.key|IN("get","post","put","patch","delete","head","options","trace"))
      | {path:$p, method:.key, op:.value};

    [ops] | .[]
    | (.op.responses // {} | keys) as $codes
    | select( (any($codes[]; test("^4"))) | not
           or (any($codes[]; test("^5"))) | not )
    | "  \(.method|ascii_upcase) \(.path): missing " +
      (if (any($codes[]; test("^4"))) then "" else "4xx " end) +
      (if (any($codes[]; test("^5"))) then "" else "5xx" end)
  '

  # For 2xx responses (except 204), require application/json content (baseline)
  run_check "2xx responses (except 204) should have application/json content" "$spec" '
    def ops:
      (.paths // {}) | to_entries[]
      | .key as $p
      | (.value // {}) | to_entries[]
      | select(.key|IN("get","post","put","patch","delete"))
      | {path:$p, method:.key, responses:(.value.responses // {})};

    [ops] | .[]
    | .responses | to_entries[]
    | select(.key|test("^2") and .key!="204")
    | select((.value.content // {}) | has("application/json") | not)
    | "  \($ENV.METHOD) \($ENV.PATH)"' \
    >/dev/null 2>&1 || true
  # The above env trick isn't portable; do it properly below:
  run_check "2xx responses (except 204) should have application/json content" "$spec" '
    def ops:
      (.paths // {}) | to_entries[]
      | .key as $p
      | (.value // {}) | to_entries[]
      | select(.key|IN("get","post","put","patch","delete"))
      | {path:$p, method:.key, responses:(.value.responses // {})};

    [ops] | .[]
    | . as $op
    | ($op.responses | to_entries[])
    | select(.key|test("^2") and .key!="204")
    | select((.value.content // {}) | has("application/json") | not)
    | "  \($op.method|ascii_upcase) \($op.path) response \(.key): missing application/json"
  '

  run_check "operationId must exist for every operation" "$spec" '
    def ops:
      (.paths // {}) | to_entries[]
      | .key as $p
      | (.value // {}) | to_entries[]
      | select(.key|IN("get","post","put","patch","delete"))
      | {path:$p, method:.key, op:.value};

    [ops] | .[]
    | select((.op.operationId // "") == "")
    | "  \(.method|ascii_upcase) \(.path): missing operationId"
  '

  run_check "operationId must be unique" "$spec" '
    def ops:
      (.paths // {}) | to_entries[]
      | .key as $p
      | (.value // {}) | to_entries[]
      | select(.key|IN("get","post","put","patch","delete"))
      | {path:$p, method:.key, operationId:(.value.operationId // "")};

    [ops | select(.operationId != "")] as $all
    | ($all | group_by(.operationId) | map(select(length>1))) as $dups
    | $dups[]?
    | "  operationId: \([.[0].operationId]) used by: " +
      (map("\(.method|ascii_upcase) \(.path)") | join(", "))
  '

  run_check "tags should exist for every operation" "$spec" '
    def ops:
      (.paths // {}) | to_entries[]
      | .key as $p
      | (.value // {}) | to_entries[]
      | select(.key|IN("get","post","put","patch","delete"))
      | {path:$p, method:.key, op:.value};

    [ops] | .[]
    | select((.op.tags // []) | length == 0)
    | "  \(.method|ascii_upcase) \(.path): missing tags[]"
  '

  # Optional: pagination on collection GET (paths without {param})
  run_check "Collection GET should define pagination params (limit/offset or page/pageSize) [optional]" "$spec" '
    def has_any_param($names):
      ((.parameters // []) | map(.name) ) as $p
      | any($names[]; $p|index(.) != null);

    (.paths // {}) | to_entries[]
    | .key as $p
    | select($p | test("\\{") | not)                # no path params => collection-ish
    | (.value.get? // empty) as $op
    | select($op != null)
    | select( (has_any_param(["limit","offset"]) or has_any_param(["page","pageSize"])) | not )
    | "  GET \($p): missing pagination (limit/offset or page/pageSize)"
  '
done

exit $fail

