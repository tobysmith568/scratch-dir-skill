#!/bin/sh
# Checks skills/scratch-dir/SKILL.md's frontmatter against the Agent Skills spec
# (https://agentskills.io/specification), mirroring the rules in the spec's own
# reference validator (agentskills/agentskills, skills-ref/src/skills_ref/validator.py)
# read directly, since running that tool needs Python packages (click, strictyaml)
# this environment doesn't have. Only decodes the one escape sequence (\") our
# description actually uses; extend the decode step below if the format ever changes
# to use others (\n, \\, etc).
#
# Usage: check-frontmatter.sh [skill-dir]
# skill-dir defaults to skills/scratch-dir, relative to this repo's root.

set -eu

scriptDir="$(cd "$(dirname "$0")/.." && pwd)"
skillDir="${1:-$scriptDir/skills/scratch-dir}"
skillMd="$skillDir/SKILL.md"

maxNameLength=64
maxDescriptionLength=1024
allowedFields="name description license allowed-tools metadata compatibility"

fail=0

report() {
  echo "FAIL: $1"
  fail=1
}

frontmatter="$(awk 'NR == 1 && $0 == "---" { p = 1; next } p && $0 == "---" { exit } p' "$skillMd")"

name="$(printf '%s\n' "$frontmatter" | sed -n 's/^name: *//p' | head -n1)"
rawDescription="$(printf '%s\n' "$frontmatter" | sed -n 's/^description: *"\(.*\)"$/\1/p' | head -n1)"
description="$(printf '%s' "$rawDescription" | sed 's/\\"/"/g')"

if [ -z "$name" ]; then
  report "name field is missing or empty"
else
  nameLength=$(printf '%s' "$name" | wc -m)
  if [ "$nameLength" -gt "$maxNameLength" ]; then
    report "name '$name' is $nameLength chars, exceeds the $maxNameLength limit"
  fi

  lower="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')"
  if [ "$name" != "$lower" ]; then
    report "name '$name' must be lowercase"
  fi

  case "$name" in
    -* | *-) report "name '$name' cannot start or end with a hyphen" ;;
  esac

  case "$name" in
    *--*) report "name '$name' cannot contain consecutive hyphens" ;;
  esac

  case "$name" in
    *[!a-z0-9-]*) report "name '$name' contains characters other than lowercase letters, digits, and hyphens" ;;
  esac

  dirName="$(basename "$skillDir")"
  if [ "$dirName" != "$name" ]; then
    report "directory name '$dirName' must match skill name '$name'"
  fi
fi

if [ -z "$description" ]; then
  report "description field is missing or empty"
else
  descriptionLength=$(printf '%s' "$description" | wc -m)
  if [ "$descriptionLength" -gt "$maxDescriptionLength" ]; then
    report "description is $descriptionLength chars, exceeds the $maxDescriptionLength limit"
  fi
fi

fields="$(printf '%s\n' "$frontmatter" | sed -n 's/^\([a-zA-Z][a-zA-Z0-9-]*\):.*/\1/p')"
for field in $fields; do
  case " $allowedFields " in
    *" $field "*) ;;
    *) report "unexpected frontmatter field '$field'" ;;
  esac
done

if [ "$fail" -eq 0 ]; then
  echo "OK: skills/scratch-dir/SKILL.md frontmatter is spec-compliant"
fi

exit "$fail"
