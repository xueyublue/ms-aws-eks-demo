# eksctl Setup Guide (Windows)

A step-by-step guide to install, configure, and verify `eksctl` on Windows before running the EKS cluster bootstrap in `EKS_DEPLOYMENT_GUIDE.md`.

---

## Prerequisites

Before using `eksctl` you need:

| Requirement | Why |
|---|---|
| AWS account | Target for the EKS cluster |
| IAM user or IAM role with sufficient permissions | `eksctl` calls AWS APIs on your behalf |
| AWS CLI v2 installed | `eksctl` delegates credential resolution to the AWS CLI |

---

## Step 1 — Install the AWS CLI v2

1. Download the installer from:  
   https://awscli.amazonaws.com/AWSCLIV2.msi

2. Run the `.msi` and follow the wizard (default options are fine).

3. Open a **new** PowerShell window and verify:
   ```powershell
   aws --version
   # Expected: aws-cli/2.x.x ...
   ```

---

## Step 2 — Create an IAM User with the Required Permissions

`eksctl` needs broad AWS permissions to create a cluster (VPC, EC2 instances, IAM roles, EKS control plane, etc.).

### 2a. Open the IAM Console

1. Log in to the [AWS Console](https://console.aws.amazon.com).
2. Navigate to **IAM → Users → Create user**.
3. Enter a username (e.g. `eksctl-admin`) and click **Next**.
4. Choose **Attach policies directly**.
5. Search for and attach the following **AWS managed policies**:

   | Policy | Purpose |
   |---|---|
   | `AmazonEC2FullAccess` | VPC, subnets, security groups, EC2 instances |
   | `IAMFullAccess` | eksctl creates IAM roles for node groups and IRSA |
   | `AWSCloudFormationFullAccess` | eksctl uses CloudFormation stacks internally |
   | `AmazonVPCFullAccess` | VPC and subnet provisioning |
   | `AmazonEKSWorkerNodePolicy` | Worker node registration |

6. After attaching the managed policies, click the user → **"Add permissions" → "Create inline policy"** → switch to the **JSON** tab and paste the following to grant EKS API access:

   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": "eks:*",
         "Resource": "*"
       }
     ]
   }
   ```

   Name it `eksctl-eks-access` → **Create policy**.

   > **Why a custom policy?** AWS does not ship a managed policy that grants a human user full EKS API access. `AmazonEKSClusterPolicy` is meant for the **cluster's IAM role**, not for a user — it does not cover `eks:CreateCluster`, `eks:DescribeClusterVersions`, etc. The inline `eks:*` policy above fills that gap.

   > **Tip:** For a quick start you can attach `AdministratorAccess` instead of all the above — restrict permissions once you are comfortable with the setup.

6. Click **Next → Create user**.

### 2b. Generate Access Keys

1. Click the newly created user → **Security credentials** tab.
2. Scroll to **Access keys** → **Create access key**.
3. Choose **Command Line Interface (CLI)** → tick the confirmation → **Next → Create access key**.
4. **Copy both values** (Access Key ID and Secret Access Key) — you will not be able to see the secret again.

---

## Step 3 — Configure the AWS CLI

Run the following in PowerShell:

```powershell
aws configure
```

You will be prompted for four values:

```
AWS Access Key ID [None]:     <paste your Access Key ID>
AWS Secret Access Key [None]: <paste your Secret Access Key>
Default region name [None]:   ap-southeast-1
Default output format [None]: json
```

This writes credentials to `~\.aws\credentials` and config to `~\.aws\config`.

### Verify AWS CLI works

```powershell
aws sts get-caller-identity
```

Expected output:
```json
{
    "UserId": "AIDA...",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/eksctl-admin"
}
```

If you see your account ID and user ARN, AWS CLI is configured correctly.

---

## Step 4 — Install eksctl

### Option A — Chocolatey (recommended)

If you have Chocolatey installed:
```powershell
choco install eksctl -y
```

### Option B — Winget

```powershell
winget install eksctl
```

### Option C — Manual download (no package manager needed)

```powershell
# 1. Download the zip
curl.exe -Lo "$env:TEMP\eksctl.zip" `
  https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Windows_amd64.zip

# 2. Extract
Expand-Archive "$env:TEMP\eksctl.zip" -DestinationPath "$env:TEMP\eksctl"

# 3. Move to a directory on your PATH
Move-Item "$env:TEMP\eksctl\eksctl.exe" "C:\Windows\System32\eksctl.exe"
```

### Verify eksctl installation

Close and reopen PowerShell, then:

```powershell
eksctl version
# Expected: 0.18x.x or later
```

---

## Step 5 — Install kubectl

`eksctl` automatically updates your kubeconfig, but `kubectl` must be installed separately to interact with the cluster.

```powershell
# Download kubectl for Windows
curl.exe -Lo "$env:TEMP\kubectl.exe" `
  "https://dl.k8s.io/release/v1.31.0/bin/windows/amd64/kubectl.exe"

# Move to a directory on your PATH.
# NOTE: Writing to C:\Windows\System32\ requires Administrator privileges.
# If you get "Access is denied", either:
#   (A) Re-run PowerShell as Administrator (right-click → Run as administrator), or
#   (B) Install to your user folder instead (no Admin needed):
#         New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\bin"
#         Move-Item "$env:TEMP\kubectl.exe" "$env:USERPROFILE\bin\kubectl.exe"
#         [System.Environment]::SetEnvironmentVariable("PATH", "$env:USERPROFILE\bin;" + [System.Environment]::GetEnvironmentVariable("PATH","User"), "User")
#       Then close and reopen PowerShell for the PATH change to take effect.
Move-Item "$env:TEMP\kubectl.exe" "C:\Windows\System32\kubectl.exe"

# Verify
kubectl version --client
```

---

## Step 6 — (Optional) Install Helm

Helm is required to install the AWS Load Balancer Controller (Step 2 of `EKS_DEPLOYMENT_GUIDE.md`).

```powershell
# Chocolatey
choco install kubernetes-helm -y

# Or winget
winget install Helm.Helm

# Verify
helm version
```

---

## Step 7 — Verify the Full Toolchain

Run all four checks in sequence:

```powershell
aws --version
eksctl version
kubectl version --client
helm version
```

All four should print version strings without errors. You are ready to run the cluster bootstrap command.

---

## Step 8 — Create the EKS Cluster

Once everything above is verified, run (using PowerShell backtick line continuation):

```powershell
eksctl create cluster `
  --name   my-eks-cluster `
  --region ap-southeast-1 `
  --nodes-min 1 `
  --nodes-max 2 `
  --node-type t3.small `
  --with-oidc `
  --alb-ingress-access
```

> **Why `t3.small` and not the free-tier `t2.micro` / `t3.micro`?**
>
> `t2.micro` and `t3.micro` have only **1 GB of RAM**. EKS reserves ~0.5 GB for system daemons
> (kubelet, kube-proxy, VPC CNI), leaving virtually no memory for application pods — the
> Spring Boot container alone requests 512 Mi. In practice, pods will stay in `Pending` or get
> OOMKilled immediately on a micro instance.
>
> `t3.small` (2 GB RAM, 2 vCPU) is the **cheapest instance type that actually works** for a
> single Spring Boot pod on EKS (~$0.021/hr, ~$15/month per node).
>
> | Instance | RAM | Free Tier? | Works for this project? |
> |---|---|---|---|
> | `t2.micro` / `t3.micro` | 1 GB | ✅ Yes (750 hrs/month, 12 months) | ❌ Too small |
> | `t3.small` | 2 GB | ❌ No | ✅ Minimum viable |
> | `t3.medium` | 4 GB | ❌ No | ✅ Comfortable headroom |
> | `m5.large` | 8 GB | ❌ No | ✅ Production-grade |

This command:
- Creates a **VPC** with public/private subnets across 2 AZs.
- Provisions the **EKS control plane** (managed by AWS — note EKS charges $0.10/hr per cluster regardless of instance type).
- Creates a **managed node group** with `t3.small` EC2 instances (1–2 nodes).
- Enables **OIDC** for IAM Roles for Service Accounts (IRSA).
- Grants the worker nodes the permissions needed for the ALB controller.
- Updates your local `~\.kube\config` with the new cluster context.

Expected duration: **10–20 minutes**.

You can follow progress live in the terminal or in the **CloudFormation** section of the AWS Console.

### Verify cluster is up

```powershell
kubectl get nodes
```

Expected: one node in `Ready` status.

```powershell
kubectl cluster-info
```

Expected: control plane and CoreDNS URLs printed.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `eksctl: command not found` | Not on PATH | Reopen PowerShell after install; check `$env:PATH` |
| `Unable to locate credentials` | AWS CLI not configured | Re-run `aws configure` |
| `UnauthorizedOperation` | IAM user missing permissions | Attach the policies listed in Step 2 |
| `AccessDeniedException: not authorized to perform: eks:DescribeClusterVersions` | Missing `eks:*` inline policy | Go to IAM → Users → eksctl-admin → Add permissions → Create inline policy → paste the `eks:*` JSON from Step 2 |
| `ResourceNotFoundException` | Wrong region | Check `--region` matches your `aws configure` default region |
| Cluster creation stalls > 30 min | CloudFormation rollback | Open AWS Console → CloudFormation → check Events tab for the failed stack |
| `error: You must be logged in to the server` | kubeconfig stale | Run `aws eks update-kubeconfig --region ap-southeast-1 --name my-eks-cluster` |

---

## Cost Warning

An EKS cluster running 24/7 will incur AWS charges even if idle:

| Resource | Approximate cost (ap-southeast-1) |
|---|---|
| EKS control plane | ~$0.10/hr (~$72/month) — charged regardless of instance type |
| `t3.small` node × 1 | ~$0.021/hr (~$15/month) |
| `t3.medium` node × 1 | ~$0.042/hr (~$30/month) |
| ALB (when Ingress is created) | ~$0.008/hr + LCU charges |
| **Total (t3.small, 1 node)** | **~$87/month** |

> **Note:** There is **no free-tier for EKS itself**. The $0.10/hr control plane fee applies from
> the moment the cluster is created, even with zero worker nodes.
> Worker node `t2.micro`/`t3.micro` hours are free-tier eligible, but those instances are too
> small to schedule any pods (see the table in Step 8).

**Always delete the cluster when not in use** (see §11 of `EKS_DEPLOYMENT_GUIDE.md`):

```powershell
eksctl delete cluster --name my-eks-cluster --region ap-southeast-1
```
