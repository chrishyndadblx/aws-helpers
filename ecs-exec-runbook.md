# ECS Exec Runbook

This runbook documents how to configure AWS SSO, set up profiles, and use `aws ecs execute-command` to exec into ECS tasks via AWS CLI.

---

## 🔑 SSO & Profiles

1. Configure SSO profile:
   ```bash
   aws configure sso --profile corp-sso
   ```

2. Generate per-account profiles (using your helper script):
   ```bash
   ./generate-profiles.sh
   ```

3. Login with the desired profile:
   ```bash
   aws sso login --profile <profile>
   ```

4. View all configured profiles:
   ```bash
   cat ~/.aws/config
   ```

⚠️ **Important:** The profile name in `~/.aws/config` must exactly match what you pass in `--profile`.

---

## 🔎 ECS Discovery

1. List all clusters:
   ```bash
   aws ecs list-clusters --profile <profile>
   ```

2. List tasks in a cluster:
   ```bash
   aws ecs list-tasks --cluster <cluster-name> --profile <profile>
   ```

⚠️ Use either the **cluster name** (`pwcuat`) or the **full ARN**. Do **not** use `cluster/<name>`.

---

## 🚀 Exec into a Container

### Alternative: Use helper script

If you don’t want to manually discover clusters and tasks, use the helper script `ecs-exec.sh`.
It will interactively let you pick the cluster and task, defaulting the container to `web`.

```bash
./ecs-exec.sh --profile <profile> --region <region>
```

Options:
- `--cluster <cluster-name-or-arn>` (skip interactive cluster selection)
- `--task <task-arn>` (skip interactive task selection)
- `--shell /bin/bash` (use bash instead of sh)


Run the command:

```bash
aws ecs execute-command   --cluster <cluster-name-or-arn>   --task <task-arn>   --container <container-name>   --command "/bin/sh"   --interactive   --region <region>   --profile <profile>
```

### ⚡️ Shortcut: use the helper script

If you don't want to manually look up clusters/tasks every time, use the helper script instead. It auto-discovers the cluster and running task and drops you straight into the `web` container.

```bash
# make it executable once
chmod +x ./ecs-exec.sh

# minimal: pick cluster & task interactively
./ecs-exec.sh --profile <profile>

# with explicit region (if your profile doesn't set one)
./ecs-exec.sh --profile <profile> --region eu-west-2

# skip prompts by specifying cluster/task
./ecs-exec.sh --profile <profile> --cluster <cluster-name-or-arn> --task <task-arn>

# use bash instead of sh if the image has it
./ecs-exec.sh --profile <profile> --shell /bin/bash
```

### Pre-requisites

1. **Enable ECS Exec** on the service/cluster:
   ```bash
   aws ecs update-service      --cluster <cluster-name>      --service <service-name>      --enable-execute-command
   ```

   Or enable at service creation time with `--enable-execute-command`.

2. **Cluster configuration** must have ECS Exec enabled:
   ```bash
   aws ecs describe-clusters      --clusters <cluster>      --include CONFIGURATIONS      --profile <profile>
   ```
   If `executeCommandConfiguration` is empty, configure it with:
   ```bash
   aws ecs update-cluster-configuration      --cluster <cluster>      --execute-command-configuration "logging=DEFAULT"
   ```

3. **Task execution role permissions** must include:
   ```json
   {
     "Effect": "Allow",
     "Action": [
       "ssmmessages:*",
       "ssm:UpdateInstanceInformation",
       "ec2messages:*",
       "logs:CreateLogStream",
       "logs:PutLogEvents",
       "kms:Decrypt",
       "kms:GenerateDataKey"
     ],
     "Resource": "*"
   }
   ```

4. Ensure your **AWS CLI version ≥ 2.1.29**.

---

## 🛠 Tooling

Install the Session Manager plugin if not already installed:

- **macOS**
  ```bash
  brew install session-manager-plugin
  ```

- **Linux (Debian/Ubuntu)**
  ```bash
  curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" -o session-manager-plugin.deb
  sudo dpkg -i session-manager-plugin.deb
  ```

Verify:
```bash
session-manager-plugin --version
```

---

## ✅ Final Checklist

- [ ] Logged in with correct SSO profile.  
- [ ] ECS cluster + service have Exec enabled.  
- [ ] Task execution role has required SSM + logs + KMS permissions.  
- [ ] Session Manager plugin installed.  
- [ ] Running `aws ecs execute-command` with **cluster name or ARN**, not `cluster/<name>`.  
- [ ] CLI version is up to date.  

Once all of the above are true, `aws ecs execute-command` should drop you into a shell inside your ECS container.

---

## ⚠️ macOS Bash Compatibility (mapfile error)

If you see:
```
./ecs-exec.sh: line 103: mapfile: command not found
```
This happens because macOS ships with Bash 3.2, which does not support `mapfile`.

### Solutions

1. **Use a `while read` loop** (script already supports this alternative):
   Replace any line like:
   ```bash
   mapfile -t clusters < <(aws ecs list-clusters ...)
   ```
   with:
   ```bash
   clusters=()
   while IFS= read -r line; do
     clusters+=("$line")
   done < <(aws ecs list-clusters ...)
   ```

   And the same for tasks.

2. **Install a newer Bash** on macOS:
   ```bash
   brew install bash
   /usr/local/bin/bash ecs-exec.sh --profile <profile>
   ```
   (On Apple Silicon, Bash is typically installed at `/opt/homebrew/bin/bash`.)

Either approach resolves the error and lets the script run correctly.
