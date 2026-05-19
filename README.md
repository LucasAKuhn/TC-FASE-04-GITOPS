# 🏗️ ToggleMaster — GitOps Repository (TC-FASE-04-GITOPS)

> Repositório de manifestos Kubernetes e Infraestrutura como Código (Terraform) do sistema ToggleMaster. Este é o repositório monitorado pelo ArgoCD — a **única fonte de verdade** para o estado do cluster.

**💻 Repositório de Aplicações (Código-fonte):** [TC-FASE-04-APPS](https://github.com/LucasAKuhn/TC-FASE-04-APPS)

---

## 📂 Estrutura do Repositório

```
TC-FASE-04-GITOPS/
├── .github/workflows/               # Automações GitHub Actions
│   └── self-healing.yml             # Self-Healing — rollout restart via repository_dispatch
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
├── scripts/
│   └── self-healing.sh              # Script kubectl de rollout restart
├── terraform/
│   ├── main.tf                      # Orquestrador principal (infra + observabilidade)
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
| **Secrets Manager** | Cofre `togglemaster/app-secrets` com credenciais do banco, master key e API keys |

### Automações declaradas no main.tf

| Recurso | Função |
| :--- | :--- |
| `helm_release.argocd` | Instala ArgoCD via Helm |
| `helm_release.metrics_server` | Instala Metrics Server via Helm |
| `helm_release.external_secrets` | Instala External Secrets Operator |
| `helm_release.kube_prometheus_stack` | Instala Prometheus + Grafana via Helm |
| `helm_release.loki` | Instala Loki (centralização de logs) |
| `helm_release.promtail` | Instala Promtail (coleta de logs dos pods) |
| `helm_release.otel_collector` | Instala OpenTelemetry Collector (gateway OTLP) |
| `kubernetes_secret_v1.app_secrets` | Cria secrets de banco + JWT |
| `kubernetes_secret_v1.argocd_repo_secret` | Cria auth do ArgoCD com GitHub |
| `null_resource.argocd_application` | Aplica ArgoCD Application via kubectl |
| `kubernetes_job_v1.db_init` | Inicializa tabelas nos bancos RDS |
| `local_file.k8s_configmap` | Gera ConfigMap com endpoints dinâmicos |
| `aws_secretsmanager_secret` | Provisiona cofre no AWS Secrets Manager |

---

## 🔭 Stack de Observabilidade (Fase 4)

O Terraform provisiona automaticamente uma stack completa de observabilidade no namespace `monitoring` do cluster EKS:

```
Microsserviços (OTLP) ──► OTel Collector (Gateway)
                              ├──► Métricas ──► Prometheus (remote write)
                              ├──► Logs     ──► Loki
                              └──► Traces   ──► New Relic (OTLP HTTP)

Promtail (DaemonSet) ──► Loki ──► Grafana (Visualização)
```

| Componente | Helm Chart | Função |
| :--- | :--- | :--- |
| **kube-prometheus-stack** | `prometheus-community/kube-prometheus-stack` v67.9.0 | Prometheus + Grafana + regras pré-configuradas |
| **Loki** | `grafana/loki` v6.29.0 | Centralização de logs (modo single-binary) |
| **Promtail** | `grafana/promtail` v6.16.6 | DaemonSet de coleta de logs dos pods |
| **OTel Collector** | `open-telemetry/opentelemetry-collector` v0.108.0 | Gateway OTLP — recebe métricas, logs e traces e roteia para backends |

### Pipelines configuradas no OTel Collector

| Pipeline | Receivers | Processors | Exporters |
| :--- | :--- | :--- | :--- |
| **Metrics** | OTLP (gRPC/HTTP) | memory_limiter, batch | Prometheus (remote write) |
| **Logs** | OTLP (gRPC/HTTP) | memory_limiter, batch | Loki |
| **Traces** | OTLP (gRPC/HTTP) | memory_limiter, batch | New Relic (OTLP HTTP) + Debug |

---

## 🛡️ Self-Healing e Resposta a Incidentes

### Automação de Self-Healing

O repositório inclui uma automação de recuperação automática para cenários de degradação:

| Componente | Arquivo | Descrição |
| :--- | :--- | :--- |
| **GitHub Action** | `.github/workflows/self-healing.yml` | Workflow acionado via `workflow_dispatch` ou `repository_dispatch` (tipo `grafana-alert`) |
| **Script auxiliar** | `scripts/self-healing.sh` | Script bash que executa `kubectl rollout restart` e aguarda estabilização |

### Fluxo do Self-Healing

```
Grafana Alert (CPU Alta / Erros 5xx)
    └─► Webhook → GitHub repository_dispatch (tipo: grafana-alert)
            └─► GitHub Action: self-healing.yml
                    ├─► Configura credenciais AWS + kubectl
                    ├─► Mostra pods (antes)
                    ├─► kubectl rollout restart deployment -n toggle-master
                    ├─► Aguarda rollout de todos os 5 serviços (timeout 120s cada)
                    └─► Mostra pods (depois)
```

### Alertas e Incidentes

| Funcionalidade | Ferramenta | Integração |
| :--- | :--- | :--- |
| **Alerta Inteligente** | Grafana Alerting | Regras configuradas via UI do Grafana |
| **Gestão de Incidentes** | PagerDuty | Contact Point do Grafana (Events API v2) |
| **ChatOps** | Discord / Slack | Notificação automática com detalhes do alerta |

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
$env:TF_VAR_github_repo_url="https://github.com/LucasAKuhn/TC-FASE-04-GITOPS.git"
$env:TF_VAR_db_password="<Sua senha do banco>"
$env:TF_VAR_master_key="<Sua Master Key>"
$env:TF_VAR_service_api_key="<Chave de API entre serviços>"
$env:TF_VAR_new_relic_license_key="<Sua License Key do New Relic>"
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
kubectl get pods -n monitoring
kubectl get ingress -n toggle-master
```

### Destruir

```powershell
cd terraform
terraform destroy -auto-approve
```

---
