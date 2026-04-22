# EKS Deployment Guide

Pre-requisites and step-by-step instructions for deploying `ms-aws-eks-demo` to Amazon EKS.

---

## Prerequisites

| Tool                     | Minimum version | Install                                    |
| ------------------------ | --------------- | ------------------------------------------ |
| AWS CLI                  | v2              | https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html |
| `kubectl`                | 1.29+           | https://kubernetes.io/docs/tasks/tools/    |
| `eksctl`                 | 0.180+          | https://eksctl.io/introduction/            |
| Docker / Docker Desktop  | 24+             | https://docs.docker.com/get-docker/        |
| Java 25 + Maven 3.9      | —               | JDK already on PATH                        |

---

## 1. Bootstrap the EKS Cluster

```bash
eksctl create cluster \
  --name   my-eks-cluster \
  --region ap-southeast-1 \
  --nodes-min 1 \
  --nodes-max 2 \
  --node-type m5.large \
  --with-oidc \
  --alb-ingress-access
```

`--with-oidc` enables IAM Roles for Service Accounts (IRSA).  
Node count is sized to match the HPA range (min 1, max 2 pods).  
The cluster creation takes ~15 minutes.

---

## 2. Install the AWS Load Balancer Controller

The Ingress manifest uses the ALB controller. Install it once per cluster.

```bash
# 1. Create an IAM policy for the controller
curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.2/docs/install/iam_policy.json
aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam_policy.json

# 2. Create an IAM service account
eksctl create iamserviceaccount \
  --cluster  my-eks-cluster \
  --namespace kube-system \
  --name     aws-load-balancer-controller \
  --attach-policy-arn arn:aws:iam::<ACCOUNT_ID>:policy/AWSLoadBalancerControllerIAMPolicy \
  --approve

# 3. Install via Helm
helm repo add eks https://aws.github.io/eks-charts && helm repo update
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName=my-eks-cluster \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

---

## 3. Create an ECR Repository

```bash
aws ecr create-repository \
  --repository-name ms-aws-eks-demo \
  --region ap-southeast-1
```

Note the repository URI — you will need it for the next steps.

---

## 4. Build and Push the Docker Image Manually

This step is handled automatically by the CI/CD pipeline on every push to `main`.  
To do it manually:

```bash
# Authenticate Docker to ECR
aws ecr get-login-password --region ap-southeast-1 | \
  docker login --username AWS --password-stdin \
  <ACCOUNT_ID>.dkr.ecr.ap-southeast-1.amazonaws.com

# Build
docker build -t ms-aws-eks-demo:latest .

# Tag and push
docker tag ms-aws-eks-demo:latest \
  <ACCOUNT_ID>.dkr.ecr.ap-southeast-1.amazonaws.com/ms-aws-eks-demo:latest
docker push \
  <ACCOUNT_ID>.dkr.ecr.ap-southeast-1.amazonaws.com/ms-aws-eks-demo:latest
```

---

## 5. Update the Deployment Image Reference

Replace `IMAGE_PLACEHOLDER` in `k8s/deployment.yaml` before applying:

```bash
IMAGE_URI="<ACCOUNT_ID>.dkr.ecr.ap-southeast-1.amazonaws.com/ms-aws-eks-demo:latest"
sed "s|IMAGE_PLACEHOLDER|$IMAGE_URI|g" k8s/deployment.yaml | kubectl apply -f -
```

---

## 6. Apply All Manifests

```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/deployment.yaml   # replace IMAGE_PLACEHOLDER first (see step 5)
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/ingress.yaml
kubectl apply -f k8s/hpa.yaml
```

---

## 7. Verify the Deployment

```bash
# Check pods are running
kubectl get pods -n todo-app

# Watch rollout
kubectl rollout status deployment/todo-app -n todo-app

# Get the ALB hostname (takes ~2 min to provision)
kubectl get ingress todo-app -n todo-app
```

Once the ALB address resolves:

```bash
ALB=http://$(kubectl get ingress todo-app -n todo-app \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

curl -X POST "$ALB/api/todos" \
  -H "Content-Type: application/json" \
  -d '{"title":"Hello EKS","completed":false}'

curl "$ALB/api/todos"
curl "$ALB/actuator/health"
```

---

## 8. Configure GitHub Actions (CI/CD)

Set the following in your GitHub repository (**Settings → Secrets and variables**):

| Kind     | Name                    | Value                                              |
| -------- | ----------------------- | -------------------------------------------------- |
| Secret   | `AWS_ACCESS_KEY_ID`     | IAM user access key (or use OIDC — recommended)    |
| Secret   | `AWS_SECRET_ACCESS_KEY` | Corresponding secret key                           |
| Variable | `AWS_REGION`            | e.g. `ap-southeast-1`                              |
| Variable | `ECR_REPOSITORY`        | e.g. `ms-aws-eks-demo`                             |
| Variable | `EKS_CLUSTER`           | e.g. `my-eks-cluster`                              |

After merging to `main` the workflow will: test → build image → push to ECR → deploy to EKS → wait for rollout.

> **Recommended:** Swap static IAM keys for [GitHub OIDC + IAM Role](https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services) to avoid long-lived credentials.

---

## 9. Scaling

The HPA is configured with **min 1 / max 2 replicas**, scaling on CPU ≥ 70% or memory ≥ 80%.

```bash
# Check current replica count and HPA status
kubectl get hpa todo-app -n todo-app

# Manually scale (bypasses HPA — HPA will reconcile back)
kubectl scale deployment todo-app --replicas=2 -n todo-app
```

To increase the ceiling, edit `k8s/hpa.yaml` (`minReplicas` / `maxReplicas`) and also raise the EKS node group to match:

```bash
eksctl scale nodegroup --cluster my-eks-cluster --nodes-min <N> --nodes-max <M> --name <nodegroup>
```

---

## 10. TLS / HTTPS (optional)

The Ingress currently listens on **HTTP port 80 only**. To enable HTTPS:

1. Request or import a certificate in **AWS Certificate Manager**.
2. In `k8s/ingress.yaml`, uncomment and fill in:
   ```yaml
   # alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
   # alb.ingress.kubernetes.io/ssl-redirect: "443"
   # alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:<region>:<account>:certificate/<id>
   ```
3. Re-apply the Ingress: `kubectl apply -f k8s/ingress.yaml`

---

## 11. Teardown

```bash
kubectl delete namespace todo-app          # removes all app resources
eksctl delete cluster --name my-eks-cluster # destroys the EKS cluster
aws ecr delete-repository --repository-name ms-aws-eks-demo --force
```
