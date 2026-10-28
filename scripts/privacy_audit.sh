#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
ROOT=${SCRIPT_DIR:h}
cd "$ROOT"

failed=0
blocked='(小美|读书人|射洪|大哥 Skill|/Users/jobsteve|XIAOMEI_DATA_DIR|cosyvoice-v3\.5-flash-[A-Za-z0-9-]+)'
secret='(sk-[A-Za-z0-9_-]{16,}|gh[pousr]_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----)'

if rg -n --hidden -S "$blocked" \
  --glob '!.git/**' --glob '!.build/**' --glob '!dist/**' --glob '!*.png' \
  --glob '!scripts/privacy_audit.sh'; then
  print -u2 "Privacy audit failed: private-project markers remain."
  failed=1
fi
if rg -n --hidden -S "$secret" \
  --glob '!.git/**' --glob '!.build/**' --glob '!dist/**' --glob '!*.png'; then
  print -u2 "Privacy audit failed: possible credential remains."
  failed=1
fi

if git rev-parse --verify HEAD >/dev/null 2>&1; then
  if git log -p --all -- . ':(exclude)*.png' | rg -n -S "$blocked|$secret"; then
    print -u2 "Privacy audit failed: blocked data exists in Git history."
    failed=1
  fi
fi

for media in ${(f)"$(find . -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.heic' -o -iname '*.webp' -o -iname '*.mp3' -o -iname '*.wav' -o -iname '*.mp4' \) -not -path './.git/*' -not -path './.build/*' -not -path './dist/*')"}; do
  [[ -z "$media" ]] && continue
  print -u2 "Privacy audit failed: unexpected personal-media format: $media"
  failed=1
done

(( failed == 0 )) || exit 1
print "PASS: no blocked private markers, credentials or personal-media formats found"
