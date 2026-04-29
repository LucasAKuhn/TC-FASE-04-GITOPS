# Security Group para proteger as Bases de Dados (Acesso apenas interno)
resource "aws_security_group" "db_sg" {
  name        = "SG-ALLOW-TM-DADOS"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"] # O tráfego não sai da VPC
  }

  ingress {
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }
}

# Grupos de Subnets Privadas para o RDS e Redis
resource "aws_db_subnet_group" "db_subnet" {
  name       = "tm-db-subnet-group"
  subnet_ids = var.private_subnets
}

resource "aws_elasticache_subnet_group" "redis_subnet" {
  name       = "tm-elasticache-subnet-group"
  subnet_ids = var.private_subnets
}

# 3 Instâncias RDS PostgreSQL (Conforme README)
locals {
  databases = ["rds-db-auth-service", "rds-db-flag-service", "rds-db-targeting-service"]
}

resource "aws_db_instance" "postgres" {
  count                  = length(local.databases)
  identifier             = local.databases[count.index]
  engine                 = "postgres"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  db_subnet_group_name   = aws_db_subnet_group.db_subnet.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  username               = "postgres"
  password               = var.db_password # Senha injetada via variavel de ambiente
  skip_final_snapshot    = true               # Essencial para conseguir destruir rapidamente depois
}

# 1 Cluster ElastiCache (Redis)
resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "elastic-cache-evaluation-service"
  engine               = "redis"
  node_type            = "cache.t3.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  subnet_group_name    = aws_elasticache_subnet_group.redis_subnet.name
  security_group_ids   = [aws_security_group.db_sg.id]
}

# 1 Tabela DynamoDB para Analytics
resource "aws_dynamodb_table" "analytics" {
  name         = "ToggleMasterAnalytics"
  billing_mode = "PAY_PER_REQUEST" # Mais barato, paga apenas o que consumir
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }
}
