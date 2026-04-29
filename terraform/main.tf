terraform {
  required_version = ">= 1.5.0"

  backend "s3" {
    bucket       = "tc4-togglemaster"
    key          = "fase4/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.1"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.7"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# --- Variáveis e Dados Globais ---
variable "db_password" {
  description = "A senha mestre dos bancos de dados RDS. Obrigatória via: $env:TF_VAR_db_password='<SUA_SENHA>'"
  type        = string
  sensitive   = true
}

data "aws_iam_role" "labrole" {
  name = "LabRole"
}

# Coletor de credenciais nativo do AWS EKS (Necessário para compatibilidade em alguns ambientes do provedor Helm)
data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_name
}

# Provedor Kubernetes (Para aplicar manifestos YAML puros)
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", "us-east-1"]
    command     = "aws"
  }
}

# Provedor Helm (Para instalar pacotes Helm, como ArgoCD)
provider "helm" {
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", "us-east-1"]
      command     = "aws"
    }
  }
}

# 1. Módulo de Rede
module "networking" {
  source = "./modules/networking"
}

# 2. Módulo EKS (Kubernetes)
module "eks" {
  source          = "./modules/eks"
  vpc_id          = module.networking.vpc_id
  public_subnets  = module.networking.public_subnets
  private_subnets = module.networking.private_subnets
  labrole_arn     = data.aws_iam_role.labrole.arn
}

# 3. Módulo de Bancos de Dados e Cache
module "database" {
  source          = "./modules/database"
  vpc_id          = module.networking.vpc_id
  private_subnets = module.networking.private_subnets
  db_password     = var.db_password
}

# 4. Módulo de Mensageria
module "messaging" {
  source = "./modules/messaging"
}

# 5. Módulo de Repositórios de Imagem
module "ecr" {
  source = "./modules/ecr"
}

# --- 6. AUTOMAÇÃO DE OBSERVABILIDADE & GITOPS (HELM) ---

# 6.1. Automação do Metrics Server (Necessário para o HPA e observabilidade de Pods)
resource "helm_release" "metrics_server" {
  name             = "metrics-server"
  repository       = "https://kubernetes-sigs.github.io/metrics-server/"
  chart            = "metrics-server"
  namespace        = "kube-system"
  create_namespace = false

  # Injeção da flag insecura exigida pelo ambiente do curso AWS Academy (que não possui TLS corporativo no Kubelet)
  set = [{
    name  = "args[0]"
    value = "--kubelet-insecure-tls"
  }]

  timeout = 600 # 10 minutos
  wait    = false

  # Aguarda os Nodes do EKS existirem fisicamente antes de tentar instalar o pacote
  depends_on = [
    module.eks
  ]
}

# 6.2. Automação do ArgoCD (Ferramenta de Continuous Deployment GitOps)
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  timeout          = 900 # 15 minutos (ArgoCD é pesado)
  wait             = false

  # Aguarda os Nodes do EKS existirem fisicamente antes de tentar instalar o pacote
  depends_on = [
    module.eks
  ]
}

# 6.2.1. Secret do ArgoCD para Repositório Privado (Zero-Touch Auth)
resource "kubernetes_secret_v1" "argocd_repo_secret" {
  metadata {
    name      = "repos-github-secret"
    namespace = "argocd"
    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }

  data = {
    url      = var.github_repo_url
    password = var.github_pat
    username = "julianopoklen"
    type     = "git"
  }

  depends_on = [
    helm_release.argocd
  ]
}

# 6.2.2. Bootstrap do Namespace (Opção 1: Robusto no Destroy)
resource "null_resource" "bootstrap_namespace" {
  triggers = {
    cluster_name = module.eks.cluster_name
  }

  provisioner "local-exec" {
    command = <<-EOT
      aws eks update-kubeconfig --region us-east-1 --name ${self.triggers.cluster_name}
      kubectl create namespace toggle-master --dry-run=client -o yaml | kubectl apply -f -
    EOT
    interpreter = ["PowerShell", "-Command"]
  }
}

# 6.2.2. Secret Protegido para a Aplicação (Zero-Touch App Secrets)
# OBS: Retornado devido ao bloqueio de OIDC do AWS Academy em IAM Roles, assumindo injeção direta pela RAM
resource "kubernetes_secret_v1" "app_secrets" {
  metadata {
    name      = "app-secrets"
    namespace = "toggle-master"
  }

  data = {
    "db-password"     = var.db_password
    "master-key"      = var.master_key
    "service-api-key" = var.service_api_key
  }

  depends_on = [
    module.eks,
    helm_release.argocd,
    null_resource.bootstrap_namespace
  ]
}

# 6.3. Automação do App GitOps (Zero-Touch Sync)
# null_resource evita o erro "no client config" do kubernetes_manifest:
# o kubectl só conecta ao cluster durante o apply (quando o EKS já existe),
# e não na fase de plan — onde o cluster ainda é um valor desconhecido.
resource "null_resource" "argocd_application" {
  triggers = {
    repo_url     = var.github_repo_url
    cluster_name = module.eks.cluster_name
  }

  provisioner "local-exec" {
    command = <<-EOT
      aws eks update-kubeconfig --region us-east-1 --name ${self.triggers.cluster_name}
      kubectl apply -f ${path.root}/../k8s/09-argo-application.yaml
    EOT
    interpreter = ["PowerShell", "-Command"]
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      aws eks update-kubeconfig --region us-east-1 --name ${self.triggers.cluster_name}
      Write-Host "--- INICIANDO LIMPEZA DE DEPENDENCIAS DE RECURSOS ---"

      # 1. Deleta Ingresses primeiro (dispara a remoção dos ALBs na AWS)
      try { kubectl delete ingress --all -A --timeout=60s } catch {}

      # 2. Varre e remove finalizers de TODOS os recursos nos namespaces alvo
      $namespaces = @("argocd", "toggle-master", "external-secrets", "monitoring")
      foreach ($ns in $namespaces) {
          Write-Host "Limpando finalizers no namespace: $ns"
          
          # Destrava o próprio Namespace (ponto crítico de travamento)
          try { kubectl patch ns $ns -p '{\"metadata\":{\"finalizers\":null}}' --type merge } catch {}

          try {
              $resources = kubectl get all,ingresses,secrets,configmaps -n $ns -o name
              if ($resources) {
                  foreach ($res in $resources) {
                      kubectl patch $res -n $ns -p '{\"metadata\":{\"finalizers\":null}}' --type merge
                  }
              }
          } catch {}
      }

      # 3. Limpeza de CRDs (Custom Resource Definitions) - Crucial para External Secrets e Prometheus
      try {
          Write-Host "Limpando finalizers de CRDs..."
          $crds = kubectl get crd -o name | Select-String "external-secrets", "argoproj", "monitoring.coreos.com"
          foreach ($crd in $crds) {
              kubectl patch $crd.ToString().Trim() -p '{\"metadata\":{\"finalizers\":null}}' --type merge
          }
      } catch {}

      # 4. Limpeza específica de Webhooks terminando o serviço
      try { kubectl delete validatingwebhookconfiguration external-secrets-webhook kube-prometheus-stack-admission --ignore-not-found } catch {}
      try { kubectl delete mutatingwebhookconfiguration external-secrets-webhook kube-prometheus-stack-admission --ignore-not-found } catch {}

      Write-Host "--- LIMPEZA DE DEPENDENCIAS DE RECURSOS CONCLUIDA ---"
    EOT
    interpreter = ["PowerShell", "-Command"]
  }

  depends_on = [
    helm_release.argocd,
    helm_release.external_secrets,
    helm_release.kube_prometheus_stack,
    helm_release.loki,
    helm_release.promtail,
    helm_release.otel_collector,
    kubernetes_secret_v1.argocd_repo_secret,
    kubernetes_secret_v1.app_secrets
  ]
}

# --- 7. DEVSECOPS: AWS SECRETS MANAGER E EXTERNAL SECRETS OPERATOR (ESO) ---

# 7.1. Cofre na AWS (Secrets Manager)
resource "aws_secretsmanager_secret" "app_secrets" {
  name                    = "togglemaster/app-secrets"
  description             = "Credenciais seguras do banco de dados e master key JWT"
  recovery_window_in_days = 0 # Permite deleção imediata no laboratório
}

resource "aws_secretsmanager_secret_version" "app_secrets_version" {
  secret_id     = aws_secretsmanager_secret.app_secrets.id
  secret_string = jsonencode({
    "db-password" = var.db_password
    "master-key"  = var.master_key
  })
}

# 7.2. Operador no Kubernetes (External Secrets)
resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true

  set = [{
    name  = "installCRDs"
    value = "true"
  }]

  timeout = 600 # 10 minutos

  depends_on = [
    module.eks
  ]
}

# --- 7.3. STACK DE OBSERVABILIDADE (Prometheus + Grafana + Loki + OTel Collector) ---

# 7.3.1. kube-prometheus-stack (Prometheus + Grafana em um único chart)
resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus-stack"
  namespace        = "monitoring"
  create_namespace = true
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = "67.9.0"
  timeout          = 900
  wait             = true

  # Alertmanager desabilitado, Grafana config, Prometheus remote write, Loki datasource
  set = [
    { name = "alertmanager.enabled",                    value = "false" },
    { name = "grafana.adminPassword",                   value = "admin" },
    { name = "grafana.service.type",                    value = "ClusterIP" },
    { name = "prometheus.prometheusSpec.enableRemoteWriteReceiver", value = "true" },
    { name = "grafana.additionalDataSources[0].name",   value = "Loki" },
    { name = "grafana.additionalDataSources[0].type",   value = "loki" },
    { name = "grafana.additionalDataSources[0].url",    value = "http://loki.monitoring.svc.cluster.local:3100" },
    { name = "grafana.additionalDataSources[0].access", value = "proxy" }
  ]

  depends_on = [module.eks]
}

# 7.3.2. Loki (Centralização de logs — modo single-binary para ambiente de teste)
resource "helm_release" "loki" {
  name             = "loki"
  namespace        = "monitoring"
  create_namespace = true
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "loki"
  version          = "6.29.0"
  timeout          = 600
  wait             = false  # Evita timeout — validar com kubectl

  # Single-binary: desabilita caches, gateway, canary e modo distribuído
  set = [
    { name = "deploymentMode",                                value = "SingleBinary" },
    { name = "loki.commonConfig.replication_factor",           value = "1" },
    { name = "loki.storage.type",                              value = "filesystem" },
    { name = "loki.auth_enabled",                              value = "false" },
    { name = "loki.schemaConfig.configs[0].from",              value = "2024-01-01" },
    { name = "loki.schemaConfig.configs[0].store",             value = "tsdb" },
    { name = "loki.schemaConfig.configs[0].object_store",      value = "filesystem" },
    { name = "loki.schemaConfig.configs[0].schema",            value = "v13" },
    { name = "loki.schemaConfig.configs[0].index.prefix",      value = "index_" },
    { name = "loki.schemaConfig.configs[0].index.period",      value = "24h" },
    { name = "singleBinary.replicas",                          value = "1" },
    { name = "read.replicas",                                  value = "0" },
    { name = "write.replicas",                                 value = "0" },
    { name = "backend.replicas",                               value = "0" },
    { name = "gateway.enabled",                                value = "false" },
    { name = "chunksCache.enabled",                            value = "false" },
    { name = "resultsCache.enabled",                           value = "false" },
    { name = "lokiCanary.enabled",                             value = "false" },
    { name = "test.enabled",                                   value = "false" },
    { name = "singleBinary.resources.requests.cpu",            value = "100m" },
    { name = "singleBinary.resources.requests.memory",         value = "256Mi" },
    { name = "singleBinary.resources.limits.memory",           value = "512Mi" }
  ]

  depends_on = [module.eks]
}

# 7.3.3. Promtail (DaemonSet — coleta automática de logs dos pods → Loki)
resource "helm_release" "promtail" {
  name             = "promtail"
  namespace        = "monitoring"
  create_namespace = true
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "promtail"
  version          = "6.16.6"
  timeout          = 300
  wait             = true

  set = [
    { name = "config.clients[0].url", value = "http://loki.monitoring.svc.cluster.local:3100/loki/api/v1/push" }
  ]

  depends_on = [helm_release.loki]
}

# 7.3.4. OpenTelemetry Collector (Gateway centralizado — recebe OTLP e roteia para backends)
resource "helm_release" "otel_collector" {
  name             = "otel-collector"
  namespace        = "monitoring"
  create_namespace = true
  repository       = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart            = "opentelemetry-collector"
  version          = "0.108.0"
  timeout          = 300
  wait             = true

  # Modo deployment (gateway centralizado, 1 réplica)
  set = [
    { name = "mode", value = "deployment" },
    { name = "image.repository", value = "otel/opentelemetry-collector-contrib" }
  ]

  values = [<<-EOT
config:
  receivers:
    otlp:
      protocols:
        grpc:
          endpoint: 0.0.0.0:4317
        http:
          endpoint: 0.0.0.0:4318

  processors:
    batch:
      timeout: 5s
      send_batch_size: 1024
    memory_limiter:
      check_interval: 1s
      limit_mib: 256
      spike_limit_mib: 64

  exporters:
    # Métricas → Prometheus (via remote write)
    prometheusremotewrite:
      endpoint: "http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090/api/v1/write"

    # Logs → Loki
    loki:
      endpoint: "http://loki.monitoring.svc.cluster.local:3100/loki/api/v1/push"

    # Traces → New Relic (descomentar quando a API key estiver disponível)
    # otlphttp/newrelic:
    #   endpoint: "https://otlp.nr-data.net"
    #   headers:
    #     api-key: "$${NEW_RELIC_LICENSE_KEY}"

    debug:
      verbosity: basic

  service:
    pipelines:
      metrics:
        receivers: [otlp]
        processors: [memory_limiter, batch]
        exporters: [prometheusremotewrite]
      logs:
        receivers: [otlp]
        processors: [memory_limiter, batch]
        exporters: [loki]
      traces:
        receivers: [otlp]
        processors: [memory_limiter, batch]
        exporters: [debug]
EOT
  ]

  depends_on = [helm_release.kube_prometheus_stack, helm_release.loki]
}

# --- 8. GITOPS AUTOMAÇÃO DE CONFIGURAÇÕES (DYNAMIC CONFIGMAP) ---

# Gera dinamicamente o arquivo YAML do ConfigMap interceptando os Endpoints fresquinhos da AWS,
# garantindo que o ArgoCD sempre receba as URLs corretas das APIs hospedadas no RDS e Redis
# sempre que o comando `terraform apply` for executado e a AWS entregar os nós.
resource "local_file" "k8s_configmap" {
  filename = "${path.root}/../k8s/00-configmap.yaml"
  content  = <<-EOT
apiVersion: v1
kind: Namespace
metadata:
  name: toggle-master
---
# --- CONFIGMAP (Endereços e Configurações Não-Sensíveis) ---
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
  namespace: toggle-master
data:
  # Hosts RDS e Redis (Gerados dinamicamente via IaC AWS)
  auth-db-host: "$${module.database.postgres_endpoints[0]}"
  flag-db-host: "$${module.database.postgres_endpoints[1]}"
  targeting-db-host: "$${module.database.postgres_endpoints[2]}"
  
  # --- CACHE ---
  REDIS_ADDR: "$${module.database.redis_endpoint}"
  
  # Nomes dos Databases
  auth-db-name: "auth_db"
  flag-db-name: "flag_db"
  targeting-db-name: "targeting_db"

  # Configurações AWS Gerais
  sqs-url: "https://sqs.us-east-1.amazonaws.com/797561896734/analytics-service-sqs"
  dynamo-table: "ToggleMasterAnalytics"
  aws-region: "us-east-1"
  
  # Portas Padrão Internas
  db-port: "5432"
  db-user: "postgres"
  redis-port: "6379"

  # OpenTelemetry Collector Endpoints (namespace monitoring)
  otel-collector-grpc: "otel-collector-opentelemetry-collector.monitoring.svc.cluster.local:4317"
  otel-collector-http: "otel-collector-opentelemetry-collector.monitoring.svc.cluster.local:4318"
EOT
}

# --- 9. GITOPS AUTOMAÇÃO DE BANCOS DE DADOS (ZERO-TOUCH DDL) ---

# Inicializa as tabelas lógicas nos bancos RDS através de um Job executado
# de dentro do cluster EKS (evitando bloqueios de VPC/Security Groups locais)
resource "kubernetes_job_v1" "db_init" {
  metadata {
    name      = "db-init-job"
    namespace = "default"
  }
  spec {
    template {
      metadata {
        labels = {
          app = "db-init"
        }
      }
      spec {
        container {
          name    = "psql-runner"
          image   = "postgres:latest"
          command = ["/bin/sh", "-c"]
          args    = [
            <<-EOF
            export PGPASSWORD='${var.db_password}'
            echo "[AUTH-SERVICE] Criando Banco..."
            psql -h ${module.database.postgres_endpoints[0]} -U postgres -d postgres -c 'CREATE DATABASE auth_db;' || true
            psql -h ${module.database.postgres_endpoints[0]} -U postgres -d auth_db -c "
              CREATE TABLE IF NOT EXISTS api_keys (
                  id SERIAL PRIMARY KEY,
                  name VARCHAR(100) NOT NULL,
                  key_hash VARCHAR(64) NOT NULL UNIQUE, 
                  is_active BOOLEAN DEFAULT true,
                  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
              );
            "
            
            echo "[FLAG-SERVICE] Criando Banco..."
            psql -h ${module.database.postgres_endpoints[1]} -U postgres -d postgres -c 'CREATE DATABASE flag_db;' || true
            psql -h ${module.database.postgres_endpoints[1]} -U postgres -d flag_db -c "
              CREATE TABLE IF NOT EXISTS flags (
                  id SERIAL PRIMARY KEY,
                  name VARCHAR(100) UNIQUE NOT NULL, 
                  description TEXT,
                  is_enabled BOOLEAN NOT NULL DEFAULT false,
                  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
                  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
              );
              CREATE OR REPLACE FUNCTION trigger_set_timestamp() RETURNS TRIGGER AS \$\$ BEGIN NEW.updated_at = NOW(); RETURN NEW; END; \$\$ LANGUAGE plpgsql;
              DROP TRIGGER IF EXISTS set_timestamp ON flags;
              CREATE TRIGGER set_timestamp BEFORE UPDATE ON flags FOR EACH ROW EXECUTE PROCEDURE trigger_set_timestamp();
            "
            
            echo "[TARGETING-SERVICE] Criando Banco..."
            psql -h ${module.database.postgres_endpoints[2]} -U postgres -d postgres -c 'CREATE DATABASE targeting_db;' || true
            psql -h ${module.database.postgres_endpoints[2]} -U postgres -d targeting_db -c "
              CREATE TABLE IF NOT EXISTS targeting_rules (
                  id SERIAL PRIMARY KEY,
                  flag_name VARCHAR(100) UNIQUE NOT NULL,
                  is_enabled BOOLEAN NOT NULL DEFAULT true,
                  rules JSONB NOT NULL,
                  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
                  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
              );
              CREATE OR REPLACE FUNCTION trigger_set_timestamp() RETURNS TRIGGER AS \$\$ BEGIN NEW.updated_at = NOW(); RETURN NEW; END; \$\$ LANGUAGE plpgsql;
              DROP TRIGGER IF EXISTS set_timestamp ON targeting_rules;
              CREATE TRIGGER set_timestamp BEFORE UPDATE ON targeting_rules FOR EACH ROW EXECUTE PROCEDURE trigger_set_timestamp();
            "
            EOF
          ]
        }
        restart_policy = "Never"
      }
    }
    backoff_limit = 4
  }

  wait_for_completion = true
  depends_on = [
    module.database,
    module.eks
  ]
}