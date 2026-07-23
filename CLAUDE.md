# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository purpose

This repo holds the demo materials for the talk **"Devs no Controle, Ops em Paz: GitOps com Argo CD"** (Portuguese). It provisions an AWS EKS cluster with OpenTofu/Terraform and installs Argo CD + the AWS Load Balancer Controller on it, to demonstrate a GitOps workflow. It is a demo/reference repo, not a production system — treat correctness of the walkthrough (README steps working end-to-end) as the main quality bar, not application code quality.

It works together with the companion repo **gitops_sample**, which is the "app repo" Argo CD points to (currently a plain nginx Deployment/Service). `k8s/argocd/repo-sample.yaml` and `k8s/argocd/helm-sample.yaml` are example Argo CD `Application` manifests meant to be adapted to point at that (or any) app repo — note their `repoURL` is a placeholder (`https://github.com/your-repo/nginx.git`) and must be updated before `kubectl apply`.

## Repository layout

- `infra/eks/` — OpenTofu/Terraform root module: VPC (`terraform-aws-modules/vpc/aws`) + EKS cluster (`terraform-aws-modules/eks/aws`, compute_config/auto-mode enabled) in `main.tf`, plus every module output re-exported in `outputs.tf`. Region is hardcoded to `us-east-1`, cluster name is `meetup-<basename(path.cwd)>`.
- `k8s/argocd/values-argocd.yaml` — Helm values for installing Argo CD itself (ALB ingress at `argocd.wesleydutra.online`, single replicas, `redis-ha` disabled — this is a small demo install, not HA).
- `k8s/argocd/helm-sample.yaml`, `k8s/argocd/repo-sample.yaml` — example Argo CD `Application` CRs (currently identical content) showing how to register a Git-backed app with Argo CD.
- `k8s/alb/alb-controller.yaml` — `IngressClass`/`IngressClassParams` for the AWS Load Balancer Controller (EKS Auto Mode), used by both the Argo CD ingress and any app ingress.

## Common commands

All commands assume the tool versions installed via `brew install opentofu awscli kubernetes-cli k9s kubectx` (see README) and valid AWS credentials (`aws configure`).

Provision infra:
```bash
cd infra/eks
tofu init
tofu plan -out meetup.plan
tofu apply "meetup.plan"
```

Point kubectl at the new cluster:
```bash
aws eks update-kubeconfig --name meetup-eks --region us-east-1
```

Install Argo CD (from repo root, after infra exists):
```bash
helm repo add argo-cd https://argoproj.github.io/argo-helm
helm repo update
helm upgrade --install argocd argo-cd/argo-cd --version 8.3.1 \
  --namespace "argocd" --create-namespace \
  --values ./k8s/argocd/values-argocd.yaml \
  --wait
```

Install the ALB controller ingress class:
```bash
kubectl apply -f k8s/alb/alb-controller.yaml
```

Get the Argo CD admin password:
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```
Argo CD UI is then reachable at `https://argocd.wesleydutra.online` (DNS/cert are tied to the AWS account this demo was built on — update the hostname and ACM certificate ARN in `values-argocd.yaml` for any other environment).

Tear down (always from `infra/eks`, in this order — never `tofu destroy` directly since Argo CD-managed k8s resources should be removed first):
```bash
cd infra/eks
tofu plan -destroy -out destroy.plan
tofu apply "destroy.plan"
```

There is no test suite, linter, or CI config in this repo. If validating changes, the README suggests (but does not wire up) `tfsec`/`checkov` for the Terraform and `kubeconform` for the Kubernetes manifests.

## Conventions and gotchas

- The ACM certificate ARN in `k8s/argocd/values-argocd.yaml` and the `repoURL`/hostnames in the sample Application manifests are environment-specific placeholders — always check these before applying to a new AWS account/domain.
- `infra/eks/main.tf` provisions an IAM role/policy for `external-dns` but the pod identity association resource is commented out — external-dns is not actually wired to the role yet.
- Suggested (not enforced) DevSecOps practices from the README: remote Terraform state (S3 + DynamoDB), KMS for EKS secrets, least-privilege IRSA, control plane logging enabled.
