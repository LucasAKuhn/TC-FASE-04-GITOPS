# 🏗️ ToggleMaster — GitOps Repository (TC-FASE-04-GITOPS)

> Repositório de manifestos Kubernetes e Infraestrutura como Código (Terraform) do sistema ToggleMaster. Este é o repositório monitorado pelo ArgoCD — a **única fonte de verdade** para o estado do cluster.

**💻 Repositório de Aplicações (Código-fonte):** [TC-FASE-04-APPS](https://github.com/julianopoklen/TC-FASE-04-APPS)

---

## 📂 Estrutura do Repositório

```
TC-FASE-04-GITOPS/
├── k8s/                             # Manifestos Kubernetes (monitorados pelo ArgoCD)
│   ├── 00-configmap.yaml            # Namespace + ConfigMap (gerado pelo Terraform)
│   ├── 01-auth.yaml                 # Deployment + Service: Auth Service
│   ├── 02-flag.yaml                 # Deployment + Service: Flag Service
│   ├── 03-targeting.yaml            # Deployment + Service: Targeting Service
│   ├── 04-evaluation.yaml           # Deployment + Service: Evaluation Service
│   ├── 05-analytics.yaml            # Deployment + Service: Analytics Service
│   ├── 06-1-ingress-controller.yaml # Nginx Ingress Controller
│   ├── 06-ingress.yaml              # Ingress — roteamento de paths
│   ├── 07-metrics-server.yaml       # Metrics Server YAML
│   ├── 08-hpa.yaml                  # Horizontal Pod Autoscaler (5 serviços)
│   ├── 09-argo-application.yaml     # CRD Application do ArgoCD
│   ├── 10-service-account.yaml      # ServiceAccount com LabRole
│   ├── 11-secret-store.yaml         # SecretStore ESO (PoC)
│   └── 12-external-secret.yaml      # ExternalSecret ESO (PoC)
├── terraform/
│   ├── main.tf                      # Orquestrador principal
│   ├── variables.tf                 # Variáveis Terraform
│   ├── outputs.tf                   # Outputs
│   └── modules/
│       ├── networking/              # VPC, Subnets, IGW, NAT
│       ├── eks/                     # Cluster EKS + Node Group
│       ├── database/                # 3x RDS + Redis + DynamoDB
│       ├── ecr/                     # 5 repositórios ECR
│       └── messaging/               # Fila SQS
├── .gitignore
└── README.md
```

---

## 🔄 Estratégia Multi-repo (GitOps)

```
TC-FASE-04-APPS                      TC-FASE-04-GITOPS (este repo)
├── Código dos microsserviços         ├── k8s/ ◄── ArgoCD monitora
├── Workflows CI/CD                   ├── terraform/
└── Dockerfiles                       └── ArgoCD Application
         │                                     ▲
         │  ┌───────────────────────┐           │
         └──► CI faz cross-repo     ├───────────┘
              push da nova tag
              de imagem Docker
```

### Fluxo de Deploy Automático

1. Dev faz push de código no **TC-FASE-04-APPS**
2. GitHub Actions faz build, scan e push da imagem no ECR
3. O workflow faz **cross-repo update** nos manifestos `k8s/0X-*.yaml` **deste repo**
4. ArgoCD detecta a diferença e faz `kubectl apply` automático no cluster EKS

---

## ☁️ Infraestrutura AWS (IaC via Terraform)

Região: `us-east-1` | Backend: S3 `tc4-togglemaster` (key `fase4/terraform.tfstate`)

### Recursos provisionados

| Componente | Detalhes |
| :--- | :--- |
| **VPC** | `tm-vpc` — CIDR 10.0.0.0/16, 3 Subnets Públicas + 3 Privadas |
| **EKS** | `tm-eks-cluster-01` — t3.small, Min 1 / Max 4 / Desired 3 |
| **RDS** | 3x PostgreSQL (auth, flag, targeting) em Subnets Privadas |
| **ElastiCache** | 1x Redis (evaluation) em Subnet Privada |
| **DynamoDB** | Tabela `ToggleMasterAnalytics` |
| **ECR** | 5 repositórios de imagens Docker |
| **SQS** | Fila de eventos de avaliação |

### Automações declaradas no main.tf

| Recurso | Função |
| :--- | :--- |
| `helm_release.argocd` | Instala ArgoCD via Helm |
| `helm_release.metrics_server` | Instala Metrics Server via Helm |
| `helm_release.external_secrets` | Instala External Secrets Operator |
| `kubernetes_secret_v1.app_secrets` | Cria secrets de banco + JWT |
| `kubernetes_secret_v1.argocd_repo_secret` | Cria auth do ArgoCD com GitHub |
| `null_resource.argocd_application` | Aplica ArgoCD Application via kubectl |
| `kubernetes_job_v1.db_init` | Inicializa tabelas nos bancos RDS |
| `local_file.k8s_configmap` | Gera ConfigMap com endpoints dinâmicos |

---

## 🚀 Quick Start (Infraestrutura)

### Pré-requisitos

| Ferramenta | Instalação |
| :--- | :--- |
| Terraform | `winget install --id "Hashicorp.Terraform"` |
| AWS CLI | `winget install --id "Amazon.AWSCLI"` |
| kubectl | `winget install --id "Kubernetes.kubectl"` |

### Passo 1 — Exportar variáveis

```powershell
$env:AWS_ACCESS_KEY_ID="<Cole da AWS Academy>"
$env:AWS_SECRET_ACCESS_KEY="<Cole da AWS Academy>"
$env:AWS_SESSION_TOKEN="<Cole da AWS Academy>"
$env:AWS_DEFAULT_REGION="us-east-1"
$env:TF_VAR_github_pat="<Seu GitHub PAT>"
$env:TF_VAR_github_repo_url="https://github.com/julianopoklen/TC-FASE-04-GITOPS.git"
$env:TF_VAR_db_password="<Sua senha do banco>"
$env:TF_VAR_master_key="<Sua Master Key>"
$env:TF_VAR_service_api_key="<Chave de API entre serviços>"
```

> ⚠️ **IMPORTANTE:** `TF_VAR_github_repo_url` deve apontar para **este** repositório (GitOps), não para o repo de aplicações.

### Passo 2 — Provisionar

```powershell
cd terraform
terraform init
terraform apply -auto-approve
```

### Passo 3 — Sincronizar ConfigMap

```powershell
aws eks update-kubeconfig --region us-east-1 --name tm-eks-cluster-01
git add k8s/00-configmap.yaml
git commit -m "chore: update dynamic configmap endpoints"
git push origin main
```

### Passo 4 — Validar

```powershell
kubectl get pods -n argocd
kubectl get pods -n toggle-master
kubectl get ingress -n toggle-master
```

### Destruir

```powershell
cd terraform
terraform destroy -auto-approve
```

---

## 📋 Tech Challenge — Fase 4

**Projeto:** ToggleMaster — Observabilidade e Resiliência Ativa  
**Deadline:** 12/05/2026
