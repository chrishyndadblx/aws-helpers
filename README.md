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

Run the command:

```bash
aws ecs execute-command   --cluster <cluster-name-or-arn>   --task <task-arn>   --container <container-name>   --command "/bin/sh"   --interactive   --region <region>   --profile <profile>
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
