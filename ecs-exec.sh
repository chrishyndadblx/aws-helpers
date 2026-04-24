#!/usr/bin/env bash
set -euo pipefail

# ecs-exec.sh — interactively exec into an ECS task's 'web' container
# Usage:
#   ./ecs-exec.sh --profile <profile> [--region <region>] [--cluster <name-or-arn>] [--task <task-arn>] [--shell </bin/sh|/bin/bash>]
#
# Notes:
# - Container name defaults to 'web' (override with --container if you really need to).
# - If --cluster or --task is omitted, you'll be prompted to select from what's available.
# - Requires: aws CLI v2, session-manager-plugin, jq. Optional: fzf for nicer selection.
#
# Exit codes:
#   1 - user/config error, 2 - dependency missing, 3 - AWS call failed

err() { echo "ERROR: $*" >&2; }
die() {
  err "$@"
  exit 1
}

need_bin() {
  command -v "$1" >/dev/null 2>&1 || return 1
}

# Defaults
PROFILE=""
REGION=""
CLUSTER=""
TASK=""
CONTAINER="web"
SHELL="/bin/bash"

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
  --profile)
    PROFILE="${2:-}"
    shift 2
    ;;
  --region)
    REGION="${2:-}"
    shift 2
    ;;
  --cluster)
    CLUSTER="${2:-}"
    shift 2
    ;;
  --task)
    TASK="${2:-}"
    shift 2
    ;;
  --container)
    CONTAINER="${2:-}"
    shift 2
    ;;
  --shell)
    SHELL="${2:-}"
    shift 2
    ;;
  -h | --help)
    sed -n '1,40p' "$0"
    exit 0
    ;;
  *)
    die "Unknown arg: $1"
    ;;
  esac
done

[[ -n "$PROFILE" ]] || die "Provide --profile <name> (SSO or static profile)."
need_bin aws || {
  err "aws CLI v2 is required."
  exit 2
}
need_bin jq || {
  err "jq is required."
  exit 2
}

# Ensure session-manager-plugin is present (needed for ecs execute-command)
if ! need_bin session-manager-plugin; then
  err "session-manager-plugin is required for ECS Exec. Install it and retry."
  exit 2
fi

# If region not provided, read from profile config
if [[ -z "${REGION}" ]]; then
  REGION="$(aws configure get region --profile "$PROFILE" || true)"
fi
[[ -n "$REGION" ]] || die "No region set. Use --region or set region in the profile."

# Helper: choose from list with fzf if available, else numbered select
choose_item() {
  local prompt="$1"
  shift
  if need_bin fzf; then
    printf "%s\n" "$@" | fzf --prompt="$prompt> " --height=15 --border
  else
    local arr=("$@")
    PS3="$prompt (enter number): "
    select opt in "${arr[@]}"; do
      if [[ -n "${opt:-}" ]]; then
        echo "$opt"
        break
      else
        echo "Invalid selection."
      fi
    done
  fi
}

# Normalize cluster input: accept name or ARN; return name for CLI calls or keep as is
normalize_cluster() {
  local c="$1"
  if [[ "$c" == arn:aws:ecs:*:*:cluster/* ]]; then
    # OK - pass ARN through
    echo "$c"
  else
    # assume name; must not be cluster/<name>
    if [[ "$c" == cluster/* ]]; then
      die "Use cluster NAME (e.g., 'mycluster') or full ARN, not 'cluster/<name>'."
    fi
    echo "$c"
  fi
}

# Resolve cluster if not provided
if [[ -z "$CLUSTER" ]]; then
  echo "Discovering ECS clusters in ${REGION} for profile ${PROFILE}..."
  clusters=()
  while IFS= read -r line; do
    clusters+=("$line")
  done < <(aws ecs list-clusters --region "$REGION" --profile "$PROFILE" --query 'clusterArns' --output json | jq -r '.[]')
  [[ ${#clusters[@]} -gt 0 ]] || die "No clusters found in region ${REGION}."
  if [[ ${#clusters[@]} -eq 1 ]]; then
    CLUSTER="${clusters[0]}"
    echo "Using only cluster found: $CLUSTER"
  else
    CLUSTER="$(choose_item "Select cluster" "${clusters[@]}")"
    [[ -n "$CLUSTER" ]] || die "No cluster selected."
  fi
fi
CLUSTER="$(normalize_cluster "$CLUSTER")"

# Resolve task if not provided
if [[ -z "$TASK" ]]; then
  echo "Discovering RUNNING tasks in cluster: $CLUSTER"
  tasks=()
  while IFS= read -r line; do
    tasks+=("$line")
  done < <(aws ecs list-tasks \
    --cluster "$CLUSTER" \
    --desired-status RUNNING \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query 'taskArns' --output json | jq -r '.[]')
  if [[ ${#tasks[@]} -eq 0 ]]; then
    die "No RUNNING tasks found. If you want STOPPED tasks, supply --task explicitly."
  fi
  if [[ ${#tasks[@]} -eq 1 ]]; then
    TASK="${tasks[0]}"
    echo "Using only task found: $TASK"
  else
    TASK="$(choose_item "Select task" "${tasks[@]}")"
    [[ -n "$TASK" ]] || die "No task selected."
  fi
fi

# Sanity checks & info
echo "Profile : $PROFILE"
echo "Region  : $REGION"
echo "Cluster : $CLUSTER"
echo "Task    : $TASK"
echo "Container: $CONTAINER"
echo "Shell    : $SHELL"
echo

# Optional: warn if execute-command not enabled at task level
enable_exec="$(aws ecs describe-tasks \
  --cluster "$CLUSTER" --tasks "$TASK" \
  --region "$REGION" --profile "$PROFILE" \
  --query 'tasks[0].enableExecuteCommand' --output text 2>/dev/null || echo "Unknown")"

if [[ "$enable_exec" == "False" ]]; then
  err "Task does not have execute-command enabled. Update the service with --enable-execute-command."
fi

# Execute the command
set -x
aws ecs execute-command \
  --cluster "$CLUSTER" \
  --task "$TASK" \
  --container "$CONTAINER" \
  --command "$SHELL" \
  --interactive \
  --region "$REGION" \
  --profile "$PROFILE"
