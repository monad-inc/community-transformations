# Canonical jq helpers for community transformations.
#
# jq has no shared library mechanism in the Monad jq operation, so each
# transform carries its own copy of the helpers it uses. This file is the
# single source of truth for those copies: a transform that defines a
# top-level function with one of the names below must use the exact body
# from this file. `go run ./tools/cmd/helpers sync` rewrites drifted copies
# and `go run ./tools/cmd/helpers check` fails when a copy differs.
#
# To change a helper, edit it here, update helpers/tests.json, run sync, and
# review the resulting transform diffs in the same PR.
#
# A "# requires: <name>" line in a helper's header names another helper it
# calls; sync inserts the dependency ahead of the helper when a transform
# lacks it.

# to_epoch_ms($ts): timestamp -> epoch milliseconds (OCSF timestamp_t, CEF
# rt/start/end). Accepts epoch numbers or numeric strings in s/ms/us/ns
# (unit inferred from magnitude), {seconds, nanos} objects, and ISO 8601
# dates or date-times with optional fractional seconds and any UTC offset.
# Returns null for null, "" and anything unparseable.
def to_epoch_ms($ts):
  def _num_ms($n):
    if   $n >= 1e17 then ($n / 1000000 | floor)
    elif $n >= 1e14 then ($n / 1000 | floor)
    elif $n >= 1e11 then ($n | floor)
    else ($n * 1000 | floor) end;
  if $ts == null or $ts == "" then null
  elif ($ts | type) == "number" then _num_ms($ts)
  elif ($ts | type) == "object" then
    (if ($ts.seconds // null) == null then null
     else ($ts.seconds * 1000 + ((($ts.nanos // 0) / 1000000) | floor)) end)
  elif ($ts | type) == "string" then
    if ($ts | test("^-?[0-9]+(\\.[0-9]+)?$")) then _num_ms($ts | tonumber)
    else
      ([$ts | ascii_upcase | capture("^(?<d>[0-9]{4}-[0-9]{2}-[0-9]{2})(?:[T ](?<t>[0-9]{2}:[0-9]{2}(?::[0-9]{2})?)(?:[.,](?<f>[0-9]+))?)? ?(?<z>Z|UTC|[+-][0-9]{2}(?::?[0-9]{2})?)?$")] | first) as $m
      | if $m == null then null
        else
          (($m.t // "00:00:00") | if length == 5 then . + ":00" else . end) as $t
          | (($m.z // "Z") | if . == "Z" or . == "UTC" then 0
              else (.[1:] | gsub(":"; "")) as $o
                | ((if (.[0:1]) == "-" then -1 else 1 end)
                   * (($o[0:2] | tonumber) * 3600 + ((if ($o | length) >= 4 then $o[2:4] else "00" end) | tonumber) * 60))
              end) as $off
          | ((($m.d + "T" + $t + "Z") | fromdateiso8601) - $off) * 1000
            + (((($m.f // "") + "000")[0:3]) | tonumber)
        end
    end
  else null end;

# to_iso($ts): timestamp -> ISO 8601 UTC with milliseconds
# ("2026-10-14T16:00:00.123Z"), for ECS @timestamp and other date fields.
# Accepts everything to_epoch_ms accepts; returns null when it returns null.
# requires: to_epoch_ms
def to_iso($ts):
  to_epoch_ms($ts) as $ms
  | if $ms == null then null
    else ($ms / 1000 | floor) as $s
      | ($s | todate | rtrimstr("Z")) + "."
        + ((1000 + (($ms - $s * 1000) | floor)) | tostring | .[1:]) + "Z"
    end;

# is_ip($s): true when $s is a string holding a literal IPv4 address
# (dotted quad, octets 0-255) or IPv6 address (RFC 4291 text form, including
# "::" compression and an embedded IPv4 tail). Host:port pairs, MAC
# addresses, timestamps, and hostnames are not IPs.
def is_ip($s):
  def _v4: test("^((25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\\.){3}(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])$");
  def _v6:
    if test("^[0-9A-Fa-f:.]+$") | not then false
    else
      (if test("\\.")
       then (split(":") | last) as $t
         | if ($t | _v4) then .[0:length - ($t | length)] + "0:0" else "x" end
       else . end) as $h
      | ($h | split("::")) as $p
      | if ($p | length) > 2 then false
        else ([$p[] | if . == "" then empty else split(":")[] end]) as $g
          | ($g | all(test("^[0-9A-Fa-f]{1,4}$")))
            and (if ($p | length) == 2 then ($g | length) <= 7 else ($g | length) == 8 end)
        end
    end;
  ($s | type) == "string" and ($s | _v4 or _v6);

# prune: recursively drop null, {} and [] values from objects and null
# elements from arrays. Empty strings are kept; use prune_blank to drop them.
def prune: walk(if type == "object" then with_entries(select(.value != null and .value != {} and .value != [])) elif type == "array" then map(select(. != null)) else . end);

# prune_blank: prune that also drops "" values from objects.
def prune_blank: walk(if type == "object" then with_entries(select(.value != null and .value != "" and .value != {} and .value != [])) elif type == "array" then map(select(. != null)) else . end);

# sev_caption($id): OCSF severity_id -> severity caption, per the OCSF enum
# (0 Unknown, 1 Informational, 2 Low, 3 Medium, 4 High, 5 Critical,
# 6 Fatal, 99 Other). Unmapped ids return "Other".
def sev_caption($id):
  { "0": "Unknown", "1": "Informational", "2": "Low", "3": "Medium", "4": "High", "5": "Critical", "6": "Fatal", "99": "Other" }[$id | tostring] // "Other";

# json_str($v) / json_str: serialize a structured value for a string field.
# null, {} and [] return null; strings pass through unquoted; anything else
# is encoded with tojson.
def json_str($v):
  if $v == null or $v == {} or $v == [] then null
  elif ($v | type) == "string" then $v
  else ($v | tojson) end;

def json_str:
  if . == null or . == {} or . == [] then null
  elif type == "string" then .
  else tojson end;
