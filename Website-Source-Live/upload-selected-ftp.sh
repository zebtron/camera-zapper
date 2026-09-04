#!/usr/bin/env bash
set -euo pipefail

# Upload only explicitly named files to the Camera Zapper web directory.
# Passwords are prompted for securely and are never stored in this script.

# Use the provider hostname because the FTP server presents a certificate for
# *.web-hosting.com. The ftp.zebtron.com alias reaches the same server but does
# not match that certificate and therefore fails secure verification in curl.
host="${ZAPPER_FTP_HOST:-premium342.web-hosting.com}"
user_name="${ZAPPER_FTP_USER:-}"
remote_dir="/zapper"
list_only=false
dry_run=false

usage() {
  cat <<'USAGE'
Usage:
  ./upload-selected-ftp.sh --list [options]
  ./upload-selected-ftp.sh [options] FILE [FILE ...]

Options:
  --host HOST          FTP host (default: premium342.web-hosting.com)
  --user USER          FTP username (or set ZAPPER_FTP_USER)
  --remote-dir PATH    Remote folder (default: /zapper)
  --list               List the remote folder without uploading
  --dry-run            Show exactly what would upload
  -h, --help           Show this help

Examples:
  ./upload-selected-ftp.sh --list
  ./upload-selected-ftp.sh --dry-run index.html
  ./upload-selected-ftp.sh index.html
  ./upload-selected-ftp.sh --remote-dir / index.html

If this FTP account is already jailed directly inside the Zapper web folder,
use --remote-dir / instead of the default /zapper.
USAGE
}

files=()
while (($#)); do
  case "$1" in
    --host)
      [[ $# -ge 2 ]] || { echo "Missing value for --host" >&2; exit 2; }
      host="$2"; shift 2 ;;
    --user)
      [[ $# -ge 2 ]] || { echo "Missing value for --user" >&2; exit 2; }
      user_name="$2"; shift 2 ;;
    --remote-dir)
      [[ $# -ge 2 ]] || { echo "Missing value for --remote-dir" >&2; exit 2; }
      remote_dir="$2"; shift 2 ;;
    --list) list_only=true; shift ;;
    --dry-run) dry_run=true; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; files+=("$@"); break ;;
    -*) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    *) files+=("$1"); shift ;;
  esac
done

[[ "$host" =~ ^[A-Za-z0-9.-]+$ ]] || { echo "Unsafe host value" >&2; exit 2; }
[[ -n "$user_name" ]] || { echo "Provide --user USER or set ZAPPER_FTP_USER." >&2; exit 2; }
[[ "$remote_dir" =~ ^/[A-Za-z0-9._/-]*$ ]] || { echo "Unsafe remote directory" >&2; exit 2; }

if ! $list_only && ((${#files[@]} == 0)); then
  echo "Name at least one file, or use --list." >&2
  usage >&2
  exit 2
fi

for local_file in "${files[@]}"; do
  [[ -f "$local_file" ]] || { echo "Not a regular file: $local_file" >&2; exit 2; }
  base_name="$(basename "$local_file")"
  [[ "$base_name" =~ ^[A-Za-z0-9._-]+$ ]] || {
    echo "Unsafe remote filename: $base_name" >&2
    echo "Use letters, numbers, dots, underscores, and hyphens only." >&2
    exit 2
  }
done

remote_dir="/${remote_dir#/}"
remote_dir="${remote_dir%/}"
[[ -n "$remote_dir" ]] || remote_dir=""
base_url="ftp://${host}${remote_dir}/"

if $dry_run; then
  echo "Host:       $host"
  echo "User:       $user_name"
  echo "Destination:${remote_dir:-/}/"
  if $list_only; then
    echo "Action:     list only"
  else
    echo "Files:"
    for local_file in "${files[@]}"; do
      printf '  %s -> %s%s\n' "$local_file" "$base_url" "$(basename "$local_file")"
    done
  fi
  exit 0
fi

if [[ -z "${ZAPPER_FTP_PASSWORD:-}" ]]; then
  read -r -s -p "FTP password for ${user_name}: " ZAPPER_FTP_PASSWORD
  echo
fi

# Keep the password out of command-line arguments and remove the temporary
# curl configuration as soon as this process exits.
credential_dir="$(mktemp -d "${TMPDIR:-/tmp}/zapper-ftp.XXXXXX")"
credential_file="${credential_dir}/curl.conf"
trap 'rm -f -- "$credential_file"; rmdir -- "$credential_dir" 2>/dev/null || true' EXIT
escaped_user="${user_name//\\/\\\\}"; escaped_user="${escaped_user//\"/\\\"}"
escaped_password="${ZAPPER_FTP_PASSWORD//\\/\\\\}"; escaped_password="${escaped_password//\"/\\\"}"
printf 'user = "%s:%s"\n' "$escaped_user" "$escaped_password" > "$credential_file"
chmod 600 "$credential_file"
unset ZAPPER_FTP_PASSWORD escaped_password

curl_common=(
  --config "$credential_file"
  --fail
  --show-error
  --silent
  --ssl-reqd
  --connect-timeout 20
  --max-time 300
)

if $list_only; then
  echo "Remote listing for ${remote_dir:-/}/"
  curl "${curl_common[@]}" --list-only "$base_url"
  exit 0
fi

echo "Uploading ${#files[@]} explicitly selected file(s) to ${remote_dir:-/}/"
for local_file in "${files[@]}"; do
  base_name="$(basename "$local_file")"
  echo "  Uploading $base_name"
  curl "${curl_common[@]}" --ftp-create-dirs --upload-file "$local_file" "${base_url}${base_name}"
done

echo "Upload complete. Remote files:"
curl "${curl_common[@]}" --list-only "$base_url"
