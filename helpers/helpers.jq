# Canonical jq helpers for community transformations.
#
# jq has no shared library mechanism in the Monad jq operation, so each
# transform carries its own copy of the helpers it uses. A transform that
# defines a top-level function with one of the names below must use the
# exact body from this file (compared after gojq normalization, so layout and
# comments don't matter). `go -C tools run ./cmd/helpers sync` rewrites
# drifted copies and `go -C tools run ./cmd/helpers check` fails when a copy
# differs or a transform defines one of these names with a different arity.
#
# Source of truth: the "Standard jq helpers" section of the transform builder
# skills in monad-inc/community (skills/*-transform-builder/SKILL.md). Do not
# edit this file by hand: change the skill, then run its
# `scripts/jq-helpers.sh export <this repo>` to regenerate this file and
# helpers/tests.json, run sync, and review the transform diffs in one PR.
#
# A "# requires: <name>" line in a helper's header names another helper it
# calls; sync inserts the dependency ahead of the helper when a transform
# lacks it.

# Epoch MILLISECONDS from any common timestamp form; null if empty or unparseable.
def to_epoch_ms($ts):
  def _n: if . == null then null else tonumber end;
  def _num_ms($n):
    if   $n >= 1e17 then ($n / 1000000 | floor)
    elif $n >= 1e14 then ($n / 1000 | floor)
    elif $n >= 1e11 then ($n | floor)
    else ($n * 1000 + 0.001 | floor) end;
  def _digits_ms($d):
    ($d | ltrimstr("-") | length) as $l
    | if   $l >= 18 then ($d[0:-6] | tonumber)
      elif $l >= 15 then ($d[0:-3] | tonumber)
      elif $l >= 12 then ($d | tonumber)
      else ($d | tonumber) * 1000 end;
  def _frac_ms($f): if $f == null then 0 else (($f + "000")[0:3] | tonumber) end;
  def _mon($m):
    if $m == null then null
    else {"JAN":1,"FEB":2,"MAR":3,"APR":4,"MAY":5,"JUN":6,
          "JUL":7,"AUG":8,"SEP":9,"OCT":10,"NOV":11,"DEC":12}[$m[0:3]] end;
  def _zone($z):
    if $z == null or $z == "" then 0
    else
      ($z | if test("^(UTC|GMT|UT)[+-]") then sub("^(UTC|GMT|UT)"; "") else . end) as $z
      | if ($z | test("^[+-][0-9]{1,2}(:?[0-9]{2})?$")) then
          ($z | capture("^(?<sg>[+-])(?<h>[0-9]{1,2}):?(?<m>[0-9]{2})?$")) as $o
          | (if $o.sg == "-" then -1 else 1 end)
            * (($o.h | tonumber) * 3600 + (($o.m // "0") | tonumber) * 60)
        else
          {"Z":0,"UTC":0,"GMT":0,"UT":0,"EST":-18000,"EDT":-14400,"CST":-21600,
           "CDT":-18000,"MST":-25200,"MDT":-21600,"PST":-28800,"PDT":-25200}[$z]
        end
    end;
  def _ms($c):
    ($c.y | tonumber | if . < 100 then (if . < 70 then . + 2000 else . + 1900 end) else . end) as $y
    | ($c.mo | _n) as $mo
    | ($c.d | tonumber) as $d
    | (($c.h // "0") | tonumber) as $h
    | (($c.mi // "0") | tonumber) as $mi
    | (($c.s // "0") | tonumber) as $s
    | _zone($c.z) as $off
    | if $mo == null or $off == null or $mo < 1 or $mo > 12 or $d < 1 or $d > 31
         or $h > 23 or $mi > 59 or $s > 60 then null
      else
        ($y - (if $mo <= 2 then 1 else 0 end)) as $yy
        | ($yy / 400 | floor) as $era
        | ($yy - $era * 400) as $yoe
        | (((153 * ($mo + (if $mo > 2 then -3 else 9 end)) + 2) / 5 | floor) + $d - 1) as $doy
        | ($yoe * 365 + ($yoe / 4 | floor) - ($yoe / 100 | floor) + $doy) as $doe
        | ($era * 146097 + $doe - 719468) as $days
        | ($days * 86400 + $h * 3600 + $mi * 60 + $s - $off) * 1000 + _frac_ms($c.f)
      end;
  def _str($raw):
    ($raw | ascii_upcase | sub("\\s*\\([^)]*\\)\\s*$"; "") | sub("^\\s+"; "") | sub("\\s+$"; "")) as $s
    | "(?<z>Z|(?:UTC|GMT|UT)?[+-][0-9]{1,2}(?::?[0-9]{2})?|[A-Z]{1,5})" as $Z
    | "(?<h>[0-9]{1,2}):(?<mi>[0-9]{2})(?::(?<s>[0-9]{2}))?(?:[.,](?<f>[0-9]+))?" as $T
    | if $s == "" then null
      elif ($s | test("^-?[0-9]+$")) then _digits_ms($s)
      elif ($s | test("^[0-9]+\\.[0-9]+$")) then
        ($s | split(".")) as $p
        | if ($p[0] | length) <= 11 then _digits_ms($p[0]) + _frac_ms($p[1])
          else _digits_ms($p[0]) end
      elif ($s | test("^/DATE\\(-?[0-9]+([+-][0-9]{4})?\\)/$")) then
        ($s | capture("(?<ms>-?[0-9]+)").ms | tonumber)
      else
        first(
          ($s | capture("^(?<y>[0-9]{4})[-/](?<mo>[0-9]{1,2})[-/](?<d>[0-9]{1,2})(?:[T ]+" + $T + ")?\\s*" + $Z + "?(?:\\s+[A-Z]{2,5})?$") | _ms(.)),
          ($s | capture("^(?<y>[0-9]{4})(?<mo>[0-9]{2})(?<d>[0-9]{2})T(?<h>[0-9]{2})(?<mi>[0-9]{2})(?<s>[0-9]{2})(?:[.,](?<f>[0-9]+))?" + $Z + "?$") | _ms(.)),
          ($s | capture("^(?:[A-Z]+,?\\s+)?(?<d>[0-9]{1,2})[ -](?<mon>[A-Z]{3,9})[ -](?<y>[0-9]{2,4})\\s+" + $T + "\\s*" + $Z + "?$") | .mo = _mon(.mon) | _ms(.)),
          ($s | capture("^(?:[A-Z]+,?\\s+)?(?<mon>[A-Z]{3,9})\\.?\\s+(?<d>[0-9]{1,2}),?\\s+(?<y>[0-9]{4})(?:,?\\s+" + $T + ")?\\s*" + $Z + "?$") | .mo = _mon(.mon) | _ms(.)),
          ($s | capture("^(?:[A-Z]+\\s+)?(?<mon>[A-Z]{3,9})\\s+(?<d>[0-9]{1,2})\\s+" + $T + "\\s+(?:" + $Z + "\\s+)?(?<y>[0-9]{4})$") | .mo = _mon(.mon) | _ms(.)),
          ($s | capture("^(?<d>[0-9]{1,2})/(?<mon>[A-Z]{3})/(?<y>[0-9]{4}):" + $T + "\\s*" + $Z + "?$") | .mo = _mon(.mon) | _ms(.))
        ) // null
      end;
  if $ts == null then null
  elif ($ts | type) == "number" then _num_ms($ts)
  elif ($ts | type) == "string" then _str($ts)
  elif ($ts | type) == "object" then
    if   $ts["$date"] != null then to_epoch_ms($ts["$date"])
    elif $ts["$numberLong"] != null then to_epoch_ms($ts["$numberLong"])
    elif $ts.seconds != null then
      ($ts.seconds | tostring | tonumber) * 1000
      + ((($ts.nanos // 0) | tostring | tonumber) / 1000000 | floor)
    else null end
  else null end;

# requires: to_epoch_ms
# UTC ISO 8601 with milliseconds ("2026-10-20T13:04:05.123Z") from any form
# to_epoch_ms accepts; null if empty or unparseable.
def to_iso($ts):
  to_epoch_ms($ts) as $ms
  | if $ms == null then null
    else
      ($ms / 1000 | floor) as $s
      | ($s | todate)[0:19] + "." + ("00" + (($ms - $s * 1000) | tostring))[-3:] + "Z"
    end;

# OCSF severity caption for a severity_id (identical in OCSF 1.0.0-1.9.0);
# null for ids outside the enum. For 99 (Other), prefer the source's own label.
def sev_caption($id):
  {"0":"Unknown","1":"Informational","2":"Low","3":"Medium","4":"High",
   "5":"Critical","6":"Fatal","99":"Other"}[$id | tostring];

# OCSF severity_id from a source severity: a label (case-insensitive) or a
# 0-10 score using the CVSS qualitative ranges (0 None -> 1, <4 Low, <7 Medium,
# <9 High, else Critical). 0 for null/empty/"unknown"; 99 for an unrecognized
# label (then keep the source label in `severity`). Map vendor-specific
# numeric scales (e.g. 1-5) explicitly instead.
def sev_to_id($s):
  def _score($n):
    if $n < 0 or $n > 10 then 99
    elif $n == 0 then 1 elif $n < 4 then 2 elif $n < 7 then 3 elif $n < 9 then 4
    else 5 end;
  if $s == null then 0
  elif ($s | type) == "number" then _score($s)
  elif ($s | type) != "string" then 99
  else
    ($s | ascii_downcase | sub("^\\s+"; "") | sub("\\s+$"; "")) as $l
    | if $l == "" or $l == "unknown" or $l == "unspecified" or $l == "untriaged" then 0
      elif ($l | test("^[0-9]+(\\.[0-9]+)?$")) then _score($l | tonumber)
      else
        {"info":1,"informational":1,"information":1,"none":1,"notice":1,"debug":1,"trace":1,
         "low":2,"minor":2,
         "medium":3,"moderate":3,"middle":3,"warning":3,"warn":3,
         "high":4,"major":4,"important":4,"error":4,
         "critical":5,"crit":5,"severe":5,"alert":5,
         "fatal":6,"emergency":6,"emerg":6}[$l] // 99
      end
  end;

# OCSF status_id from a source status word (case-insensitive; "_"/"-" read as
# spaces) or boolean. $kind picks the class's enum:
#   "event"    - activity classes: 1 Success, 2 Failure
#   "finding"  - finding classes (OCSF 1.1.0+): 1 New, 2 In Progress,
#                3 Suppressed, 4 Resolved. Archived (5) and Deleted (6) exist
#                only in newer versions, so they map to 99; set them explicitly
#                when the target version has them.
#   "incident" - Incident Finding: 1 New, 2 In Progress, 3 On Hold,
#                4 Resolved, 5 Closed
# 0 for null/empty/"unknown"; 99 for unrecognized values; null for an unknown $kind.
def status_to_id($s; $kind):
  ($s | if type == "string" then ascii_downcase | gsub("[\\s_-]+"; " ") | sub("^ "; "") | sub(" $"; "")
        elif type == "boolean" then tostring else null end) as $l
  | {"event": {"success":1,"succeeded":1,"successful":1,"ok":1,"pass":1,"passed":1,
               "allow":1,"allowed":1,"accepted":1,"complete":1,"completed":1,"true":1,
               "failure":2,"failed":2,"fail":2,"error":2,"deny":2,"denied":2,
               "blocked":2,"rejected":2,"unsuccessful":2,"false":2},
     "finding": {"new":1,"open":1,"opened":1,"active":1,"unresolved":1,"reopened":1,"detected":1,
                 "in progress":2,"investigating":2,"triaged":2,"acknowledged":2,"assigned":2,
                 "suppressed":3,"ignored":3,"muted":3,"dismissed":3,"false positive":3,
                 "risk accepted":3,"accepted risk":3,"snoozed":3,"exception":3,
                 "resolved":4,"fixed":4,"remediated":4,"closed":4,"mitigated":4},
     "incident": {"new":1,"open":1,"opened":1,"triggered":1,"active":1,
                  "in progress":2,"investigating":2,"acknowledged":2,"assigned":2,"mitigating":2,
                  "on hold":3,"paused":3,"snoozed":3,"pending":3,
                  "resolved":4,"mitigated":4,"fixed":4,
                  "closed":5}}[$kind] as $map
  | if $map == null then null
    elif $l == null or $l == "" or $l == "unknown" then 0
    else ($map[$l] // 99) end;

# OCSF status caption for a status_id, using the same $kind as status_to_id
# ("event" also covers the remediation classes' extra values). null outside
# the enum or for an unknown $kind.
def status_caption($id; $kind):
  {"event": {"0":"Unknown","1":"Success","2":"Failure","3":"Does Not Exist","4":"Partial",
             "5":"Unsupported","6":"Error","99":"Other"},
   "finding": {"0":"Unknown","1":"New","2":"In Progress","3":"Suppressed","4":"Resolved",
               "5":"Archived","6":"Deleted","99":"Other"},
   "incident": {"0":"Unknown","1":"New","2":"In Progress","3":"On Hold","4":"Resolved",
                "5":"Closed","99":"Other"}}[$kind][$id | tostring];

# CEF severity (integer 0-10) from a label (case-insensitive) or a 0-10
# number (floored and clamped). Buckets follow the CEF spec: Low 0-3,
# Medium 4-6, High 7-8, Very-High 9-10. null for null, empty, "unknown", or
# unrecognized input; map vendor-specific scales explicitly.
def cef_sev($s):
  if $s == null then null
  elif ($s | type) == "number" then ([[($s | floor), 0] | max, 10] | min)
  elif ($s | type) != "string" then null
  else
    ($s | ascii_downcase | sub("^\\s+"; "") | sub("\\s+$"; "")) as $l
    | if ($l | test("^[0-9]+(\\.[0-9]+)?$")) then cef_sev($l | tonumber)
      else
        {"none":0,"debug":0,"trace":0,"info":1,"informational":1,"information":1,"notice":1,
         "low":3,"minor":3,
         "medium":5,"moderate":5,"middle":5,"warning":5,"warn":5,
         "high":7,"major":7,"important":7,"error":7,
         "very-high":9,"very high":9,"critical":9,"crit":9,"severe":9,"alert":9,
         "fatal":10,"emergency":10,"emerg":10}[$l]
      end
  end;

# True for a real boolean true or the string "true" (any case). Sources send
# both for the same field, and `== "true"` silently misses a boolean.
def truthy($v):
  ($v == true) or (($v | type) == "string" and ($v | ascii_downcase) == "true");

# True only for a valid IPv4 or IPv6 address string (no port, no zone, no
# CIDR). Guard every ip-typed field with it.
def is_ip($s):
  def _v4: test("^((25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])[.]){3}(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])$");
  def _v6:
    if (contains(":") and test("^[0-9A-Fa-f:.]+$")) | not then false
    else
      split("::") as $p
      | if ($p | length) > 2 then false
        else
          [$p[] | select(. != "") | split(":")[]] as $g
          | (($g | length) > 0 and ($g[-1] | contains("."))) as $tail4
          | (if $tail4 then $g[0:-1] else $g end) as $hex
          | (($hex | length) + (if $tail4 then 2 else 0 end)) as $n
          | (if $tail4 then ($g[-1] | _v4) else true end)
            and all($hex[]; test("^[0-9A-Fa-f]{1,4}$"))
            and (if ($p | length) == 2 then $n <= 7 else $n == 8 end)
        end
    end;
  ($s | type) == "string" and ($s | _v4 or _v6);

# Serialize a nested value to a JSON string (to keep vendor blobs from
# exploding a downstream index mapping). Strings pass through unchanged;
# null, {} and [] give null.
# Also usable as a filter: `.x | json_str`.
def json_str($v):
  if $v == null or $v == {} or $v == [] then null
  elif ($v | type) == "string" then $v
  else ($v | tojson) end;
def json_str: json_str(.);

# Sorted unique values, dropping null and "", from an array whose items may
# themselves be arrays (flattened one level). A single scalar is treated as a
# one-item array. [] when nothing remains. For ECS related.* fields.
def present_unique($arr):
  [ (if ($arr | type) == "array" then $arr[] elif $arr == null then empty else $arr end)
    | if type == "array" then .[] else . end
    | select(. != null and . != "") ] | unique;

# Recursively drop null, {} and [] from objects and arrays (bottom-up, so a
# parent emptied by pruning is dropped too). Keeps "", 0 and false.
def prune:
  walk(if type == "object" then with_entries(select(.value != null and .value != {} and .value != []))
       elif type == "array" then map(select(. != null and . != {} and . != []))
       else . end);

# Like prune, but also drops empty strings (""). Keeps 0 and false.
def prune_blank:
  walk(if type == "object" then with_entries(select(.value != null and .value != "" and .value != {} and .value != []))
       elif type == "array" then map(select(. != null and . != "" and . != {} and . != []))
       else . end);
