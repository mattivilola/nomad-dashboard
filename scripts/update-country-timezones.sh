#!/bin/zsh
set -euo pipefail

# Regenerates Packages/NomadCore/Sources/NomadCore/Resources/country-timezones.json from the IANA time
# zone database's zone.tab (public domain), which maps each ISO 3166-1 country to its IANA time zones.
# Run it manually when the tz database changes; the app itself never fetches this data.
#
# Usage: scripts/update-country-timezones.sh [--zoneinfo DIR] [--output FILE]
#   --zoneinfo DIR  directory with zone.tab and +VERSION (default: /usr/share/zoneinfo, which macOS ships)
#   --output FILE   where to write the JSON (default: the bundled resource)
#
# The output is deterministic: countries are sorted by code, and a country's zones keep the order of
# zone.tab. There is no timestamp, so running it twice on the same tzdata gives identical bytes.

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h}"

ZONEINFO_DIR="/usr/share/zoneinfo"
OUTPUT="$REPO_ROOT/Packages/NomadCore/Sources/NomadCore/Resources/country-timezones.json"

while (( $# > 0 )); do
  case "$1" in
    --zoneinfo) ZONEINFO_DIR="$2"; shift 2 ;;
    --output) OUTPUT="$2"; shift 2 ;;
    -h|--help) sed -n '3,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 64 ;;
  esac
done

ZONE_TAB="$ZONEINFO_DIR/zone.tab"
if [[ ! -r "$ZONE_TAB" ]]; then
  echo "Cannot read $ZONE_TAB" >&2
  exit 66
fi

VERSION=""
if [[ -r "$ZONEINFO_DIR/+VERSION" ]]; then
  VERSION="$(tr -d '[:space:]' < "$ZONEINFO_DIR/+VERSION")"
fi
VERSION="${VERSION:-unknown}"

mkdir -p "${OUTPUT:h}"

# zone.tab columns: country code, coordinates, time zone, comments. Comment lines start with #.
grep -v '^#' "$ZONE_TAB" | awk -F '\t' -v version="$VERSION" '
  NF >= 3 && $1 ~ /^[A-Z][A-Z]$/ && $3 ~ /^[A-Za-z0-9_+\/-]+$/ {
    key = $1 SUBSEP $3
    if (!(key in seen)) {
      seen[key] = 1
      zones[$1] = (($1 in zones) ? zones[$1] ", " : "") "\"" $3 "\""
      if (!($1 in known)) { known[$1] = 1; codes[++count] = $1 }
    }
  }
  END {
    # Insertion sort keeps the output independent of the awk implementation.
    for (i = 2; i <= count; i++) {
      value = codes[i]
      for (j = i - 1; j >= 1 && codes[j] > value; j--) { codes[j + 1] = codes[j] }
      codes[j + 1] = value
    }
    printf "{\n  \"source\": \"IANA tz database zone.tab (public domain)\",\n  \"tzdataVersion\": \"%s\",\n  \"zones\": {\n", version
    for (i = 1; i <= count; i++) {
      printf "    \"%s\": [%s]%s\n", codes[i], zones[codes[i]], (i < count ? "," : "")
    }
    printf "  }\n}\n"
  }
' > "$OUTPUT"

echo "Wrote $OUTPUT (tzdata $VERSION)"
