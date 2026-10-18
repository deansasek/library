#!/bin/zsh
# Fails when Sources/Library breaks the theming conventions. It checks for:
#   color      hardcoded colors: Color(red:), NSColor(red:), named colors such as .red or .white as a foreground,
#              fill, background, or tint, and NSColor.white / NSColor.black / Color.white / Color.black.
#   font       fixed point sizes: .font(.system(size:)) and NSFont.systemFont(ofSize: <number>).
#   opacity    .opacity() on a text foreground. Use a semantic style such as .secondary or .tertiary.
#   button     a button or menu whose label is only an SF Symbol image, with no accessibilityLabel, help, or text.
# Each rule can be excepted per line in Tests/theming-allowlist.txt (tab-separated: file, exact trimmed line, reason).
# An entry that no longer matches any line fails too, so the list stays current. Uses only zsh, grep, sed, and awk.
set -euo pipefail
cd "$(dirname "$0")/.."

root="Sources/Library"
allowlist="Tests/theming-allowlist.txt"
violations="$(mktemp)"
trap 'rm -f "$violations"' EXIT

# A missing source tree or allowlist must fail, not pass with nothing checked.
if [[ ! -d "$root" ]]; then
    print -ru2 -- "Theming lint failed: $root is missing, so there is nothing to check."
    exit 1
fi
if [[ ! -f "$allowlist" ]]; then
    print -ru2 -- "Theming lint failed: $allowlist is missing, so no exception can be checked."
    exit 1
fi

# Lines are printed as: rule, file, line number, trimmed text.
# grep exits 1 when nothing matches, which is fine; any other failure means the tree could not be searched.
grep_rule() {
    local rule="$1" pattern="$2" matches grep_status=0
    matches="$(grep -rnE --include='*.swift' -- "$pattern" "$root")" || grep_status=$?
    if (( grep_status > 1 )); then
        print -ru2 -- "Theming lint failed: could not search $root for $rule (grep exit $grep_status)."
        exit 1
    fi
    [[ -n "$matches" ]] || return 0
    print -r -- "$matches" \
        | awk -F: -v rule="$rule" '{ file=$1; n=$2; sub(/^[^:]*:[^:]*:/, ""); gsub(/^[ \t]+|[ \t]+$/, ""); print rule "\t" file "\t" n "\t" $0 }' \
        >> "$violations"
}

grep_rule color   'Color\(red:|NSColor\(red:|\.(foregroundColor|foregroundStyle|background|fill|tint|stroke)\(\.?(red|black|white|green|blue|gray)\)|NSColor\.(white|black)\b|Color\.(white|black)\b'
grep_rule font    '\.system\(size:|systemFont\(ofSize: *[0-9]'
grep_rule opacity '(foregroundStyle|foregroundColor)\(.*\.opacity\('

# An Image(systemName:) that is the label of a Button or Menu. The control is found from the line with the image, the
# line before it (label: {), or the line that opens a trailing closure. It passes when accessibilityLabel or help is
# attached within the next few lines, or when the label also has text or a Label.
swift_files=("${(@f)$(find "$root" -name '*.swift' | sort)}")
if [[ -z "${swift_files[*]}" ]]; then
    print -ru2 -- "Theming lint failed: no Swift files under $root, so nothing was checked."
    exit 1
fi
for file in "${swift_files[@]}"; do
    awk -v file="$file" '
        function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
        { L[FNR] = $0 }
        END {
            for (i = 1; i <= FNR; i++) {
                if (L[i] !~ /Image\(systemName:/ || L[i] ~ /Label\(/) continue
                cand = 0
                if (L[i] ~ /Button/) cand = i
                else if (L[i-1] ~ /label: *\{/) {
                    if (L[i-1] ~ /Button/) cand = i - 1
                    for (k = i - 2; !cand && k >= 1 && k >= i - 8; k--) {
                        if (L[k] ~ /Button/) { cand = k; break }
                        if (L[k] ~ /Menu|Label\(|ShareLink|Text\(|Picker|Toggle|Section/) break
                    }
                } else if (L[i-1] ~ /Button.*\{ *$/) cand = i - 1
                if (!cand) continue
                text = 0; named = 0
                for (k = cand; k <= i + 6 && k <= FNR; k++) {
                    if (k > i && L[k] ~ /Button|Menu/) break
                    if (L[k] ~ /Text\(|Label\(/) text = 1
                    if (L[k] ~ /accessibilityLabel\(|\.help\(/) named = 1
                }
                if (!text && !named) print "button\t" file "\t" i "\t" trim(L[i])
            }
        }' "$file" >> "$violations"
done

# Drop the lines the allowlist excepts, and report allowlist entries that no longer match anything.
# The awk status must fail the script: a read error here would otherwise turn into a false pass.
awk_status=0
result="$(awk -F'\t' '
    FILENAME == ARGV[1] {
        if ($0 ~ /^#/ || NF < 3) next
        key = $1 "\t" $2; allow[key] = $3; order[++count] = key
        next
    }
    {
        key = $2 "\t" $4
        if (key in allow) { used[key] = 1; next }
        printf "FAIL %s  %s:%s  %s\n", $1, $2, $3, $4
        failed = 1
    }
    END {
        for (i = 1; i <= count; i++) if (!(order[i] in used)) {
            split(order[i], parts, "\t")
            printf "FAIL allowlist entry no longer matches a line: %s  %s\n", parts[1], parts[2]
            failed = 1
        }
        exit failed
    }' "$allowlist" "$violations")" || awk_status=$?

if [[ -n "$result" ]]; then
    print -r -- "$result"
fi
if (( awk_status != 0 )); then
    print -r -- "Theming lint failed. Fix the line, or add an exception with a reason to $allowlist."
    exit 1
fi
print "Theming lint passes."
