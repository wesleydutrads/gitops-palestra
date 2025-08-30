# Palestra GitOps com Argo CD — Infra + Demo

Este repositório contém os arquivos de demonstração para a palestra **"Devs no Controle, Ops em Paz: GitOps com Argo CD"**.

## 📋 Pré-requisitos

Instale os seguintes pacotes (usando Homebrew no Linux):

```bash
brew install opentofu awscli kubernetes-cli k9s kubectx
```

Configurar credenciais AWS:

```bash
aws configure
```

## 🚀 Passo a passo

### 1. Provisionar Infra (VPC + EKS + Addons)

```bash
cd infra/eks
tofu init
tofu plan  -out meetup.plan
tofu apply "meetup.plan"
```

Atualizar kubeconfig:

```bash
aws eks update-kubeconfig --name meetup-eks --region us-east-1
```

### 2. Instalar ArgoCD

- Argo CD (via Helm)

```bash
helm repo add argo-cd https://argoproj.github.io/argo-helm
helm repo update
helm upgrade --install argocd argo-cd/argo-cd  --version 8.3.1 \
  --namespace "argocd" --create-namespace \
  --values ./k8s/argocd/values-argocd.yaml \
  --wait
```

### 3. Configurar ALB Controller

```bash
kubectl apply -f k8s/alb/alb-controller.yaml
```

### 4. Acessar o Argo CD

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

Abra no navegador: `https://argocd.wesleydutra.online`

### 5. Limpeza

```bash
cd infra/eks
tofu plan -destroy -out destroy.plan
tofu apply "destroy.plan"
```

## 🛡️ Práticas DevSecOps sugeridas

- State remoto (S3 + DynamoDB)
- KMS para secrets do EKS
- IRSA com permissões mínimas
- Control plane logs habilitados
- Validações com tfsec/checkov/kubeconform
