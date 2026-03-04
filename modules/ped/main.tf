# ============================================================
# PPE Certification Platform - AWS Infrastructure Components
# HLD-PPE-2026-001 | eu-west-2 (London) | Multi-AZ
# Classification: OFFICIAL-SENSITIVE
#
# Networking model: no IGW / NAT Gateway.
# All EC2 instances (bastion, DMZ, APP) are placed in public
# subnets and reachable via individually assigned Elastic IPs.
# Security group rules enforce all traffic flow restrictions.
#
# Context references:
#   HLD-PPE-2026-001  - High-Level Design Document
#   TM-PPE-2026-001   - STRIDE Threat Model
# ============================================================

# --- SNS: ALERTING TOPIC (HLD §6.1 Alerting Strategy) ---
# Receives CloudWatch alarms for CPU, memory, RDS connections, 5xx errors,
# backup failures, and certificate expiry. Subscribe Encircle ops team email.

# --- DATA: AWS ACCOUNT ID (used for globally-unique resources like S3 bucket names) ---
data "aws_caller_identity" "current" {}

resource "aws_sns_topic" "alerts" {
  name              = "ped-alerts-${var.environment}"
  kms_master_key_id = aws_kms_key.main.id
  tags = { Name = "ped-alerts" }
}

resource "aws_sns_topic_subscription" "alerts_email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.ops_alert_email
}

# --- KMS: CUSTOMER-MANAGED ENCRYPTION KEY ---
# All data at rest (RDS, EFS, S3, EBS, SNS, CloudWatch Logs) encrypted with CMK (HLD §5.8.3)
#
# FIX: Add an explicit key policy that allows CloudWatch Logs (eu-west-2) to use the key for log-group encryption.
# Without this, CloudWatch Logs CreateLogGroup fails with:
#   AccessDeniedException: The specified KMS key does not exist or is not allowed...
data "aws_iam_policy_document" "kms_main" {
  # Keep full admin control for the account root (standard AWS baseline)
  statement {
    sid    = "EnableIAMUserPermissions"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }

  # Allow CloudWatch Logs service in this region to use the key
  statement {
    sid    = "AllowCloudWatchLogsUseOfKey"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["logs.eu-west-2.amazonaws.com"]
    }

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey"
    ]

    resources = ["*"]
  }
}

resource "aws_kms_key" "main" {
  description             = "PPE Platform CMK - data at rest encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  # FIX: explicit key policy (see above)
  policy = data.aws_iam_policy_document.kms_main.json

  tags = { Name = "ped-cmk", Classification = "OFFICIAL-SENSITIVE" }
}

resource "aws_kms_alias" "main" {
  name          = "alias/ped-platform-${var.environment}"
  target_key_id = aws_kms_key.main.key_id
}

# --- CLOUDWATCH LOG GROUPS ---
# Centralised log retention for VPC Flow Logs, EC2 syslog/auth, and RDS audit (HLD §6.1)
resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name              = "/ped/${var.environment}/vpc-flow-logs"
  retention_in_days = 90 # HLD §6.2 - 90-day retention aligns with backup policy
  kms_key_id        = aws_kms_key.main.arn
  tags = { Name = "ped-lg-vpc-flow-logs" }
}

resource "aws_cloudwatch_log_group" "ec2" {
  name              = "/ped/${var.environment}/ec2"
  retention_in_days = 90
  kms_key_id        = aws_kms_key.main.arn
  tags = { Name = "ped-lg-ec2" }
}

resource "aws_cloudwatch_log_group" "rds_audit" {
  name              = "/ped/${var.environment}/rds-audit"
  retention_in_days = 90
  kms_key_id        = aws_kms_key.main.arn
  tags = { Name = "ped-lg-rds-audit" }
}

# --- IAM: EC2 INSTANCE PROFILE ---
# Grants EC2 instances least-privilege access to Secrets Manager (DB credentials),
# SSM Session Manager (STRIDE R1 - reduces SSH surface), and CloudWatch Logs (HLD §6.1).
resource "aws_iam_role" "ec2_instance_role" {
  name = "ped-ec2-instance-role-${var.environment}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = { Name = "ped-ec2-instance-role" }
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.ec2_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Least-privilege: allow read of PED-scoped secrets only (STRIDE R8 - credential protection)
resource "aws_iam_role_policy" "secrets_read" {
  name = "ped-secrets-read"
  role = aws_iam_role.ec2_instance_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
      Resource = "arn:aws:secretsmanager:eu-west-2:*:secret:ped/*"
    }]
  })
}

resource "aws_iam_instance_profile" "ec2" {
  name = "ped-ec2-instance-profile-${var.environment}"
  role = aws_iam_role.ec2_instance_role.name
}

# --- IAM: VPC FLOW LOGS ROLE ---
resource "aws_iam_role" "flow_logs_role" {
  name = "ped-vpc-flow-logs-role-${var.environment}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "flow_logs_policy" {
  name = "ped-flow-logs-policy"
  role = aws_iam_role.flow_logs_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogGroups", "logs:DescribeLogStreams"]
      Resource = aws_cloudwatch_log_group.vpc_flow_logs.arn
    }]
  })
}

# --- NETWORK: VPC ---
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { Name = "ped-vpc-${var.environment}" }
}

# VPC Flow Logs - ALL traffic captured to CloudWatch (STRIDE §7.4 / HLD §5.8.2)
# Monitors outbound access patterns; key input for anomaly detection.
resource "aws_flow_log" "main" {
  vpc_id          = aws_vpc.main.id
  traffic_type    = "ALL"
  iam_role_arn    = aws_iam_role.flow_logs_role.arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_logs.arn
  tags = { Name = "ped-vpc-flow-logs" }
}

# --- AMI: DEBIAN 12 ARM64 (Graviton) ---
# Looks up the specific Debian 12 ARM64 Golden Build by name at plan time.
# Avoids hardcoding AMI IDs which are region-specific and change with each release.
data "aws_ami" "debian" {
  most_recent = true
  owners      = ["136693071363"] # Debian official AWS account

  filter {
    name   = "name"
    values = ["debian-12-arm64-20260210-2384"]
  }

  filter {
    name   = "architecture"
    values = ["arm64"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# --- SUBNETS: 2 tiers across 2 AZs (eu-west-2a, eu-west-2b) ---

# Public subnets - hosts bastion HA pair, NGINX (DMZ), and Drupal APP instances.
# No auto-assigned public IPs; each EC2 instance is assigned an explicit Elastic IP below.
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.${count.index}.0/24"
  availability_zone       = "eu-west-2${count.index == 0 ? "a" : "b"}"
  map_public_ip_on_launch = false
  tags = { Name = "ped-subnet-public-${count.index == 0 ? "a" : "b"}", Tier = "Public" }
}

# Data subnets - isolated, hosts RDS MariaDB, ElastiCache Redis, and EFS mount targets.
# No route to internet; reachable from APP instances via VPC-local routing only.
resource "aws_subnet" "data" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index + 20}.0/24"
  availability_zone = "eu-west-2${count.index == 0 ? "a" : "b"}"
  tags = { Name = "ped-subnet-data-${count.index == 0 ? "a" : "b"}", Tier = "Data" }
}

# --- SECURITY GROUPS (HLD §5.5.3 - layered flow enforcement) ---

# Bastion HA pair: SSH from Encircle VPN egress only - never open to internet (HLD §5.8.4)
resource "aws_security_group" "bastion_sg" {
  vpc_id      = aws_vpc.main.id
  description = "Bastion HA pair - SSH restricted to Encircle VPN egress IP"
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.encircle_vpn_cidr] # Encircle VPN egress only - NOT 0.0.0.0/0
  }
  egress { from_port = 0; to_port = 0; protocol = "-1"; cidr_blocks = ["0.0.0.0/0"] }
  tags = { Name = "ped-sg-bastion" }
}

# DMZ (NGINX): HTTPS from Cloudflare IPs only; SSH from bastion only (HLD §5.5.3)
resource "aws_security_group" "dmz_sg" {
  vpc_id      = aws_vpc.main.id
  description = "NGINX DMZ - HTTPS from Cloudflare IP ranges only"
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.cloudflare_ip_ranges # Cloudflare published egress ranges
  }
  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
  }
  egress { from_port = 0; to_port = 0; protocol = "-1"; cidr_blocks = ["0.0.0.0/0"] }
  tags = { Name = "ped-sg-dmz" }
}

# APP (Drupal): PHP-FPM from DMZ only; SSH from bastion only
resource "aws_security_group" "app_sg" {
  vpc_id      = aws_vpc.main.id
  description = "Drupal APP tier - ingress from DMZ and bastion only"
  ingress {
    from_port       = 9000
    to_port         = 9000
    protocol        = "tcp"
    security_groups = [aws_security_group.dmz_sg.id]
  }
  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
  }
  egress { from_port = 0; to_port = 0; protocol = "-1"; cidr_blocks = ["0.0.0.0/0"] }
  tags = { Name = "ped-sg-app" }
}

# RDS MariaDB: port 3306 from APP tier only
resource "aws_security_group" "rds_sg" {
  vpc_id      = aws_vpc.main.id
  description = "RDS MariaDB - port 3306 from APP tier only"
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.app_sg.id]
  }
  tags = { Name = "ped-sg-rds" }
}

# ElastiCache Redis: port 6379 from APP tier only
resource "aws_security_group" "redis_sg" {
  vpc_id      = aws_vpc.main.id
  description = "ElastiCache Redis - port 6379 from APP tier only"
  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.app_sg.id]
  }
  tags = { Name = "ped-sg-redis" }
}

# EFS: NFS port 2049 from APP tier only
resource "aws_security_group" "efs_sg" {
  vpc_id      = aws_vpc.main.id
  description = "EFS - NFS port 2049 from APP tier only"
  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.app_sg.id]
  }
  tags = { Name = "ped-sg-efs" }
}

# --- BASTION HA PAIR (one per AZ - HLD §5.8.4) ---
resource "aws_instance" "bastion" {
  count                  = 2
  ami                    = data.aws_ami.debian.id
  instance_type          = "t4g.nano"
  subnet_id              = aws_subnet.public[count.index].id
  vpc_security_group_ids = [aws_security_group.bastion_sg.id]
  key_name               = var.bastion_key_name
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  root_block_device {
    volume_size = 20
    encrypted   = true
    kms_key_id  = aws_kms_key.main.arn
    volume_type = "gp3"
  }

  metadata_options { http_tokens = "required" } # IMDSv2 enforced

  tags = {
    Name = "ped-bastion-${count.index == 0 ? "a" : "b"}"
    Role = "Bastion"
    AZ   = "eu-west-2${count.index == 0 ? "a" : "b"}"
  }
}

resource "aws_eip" "bastion" {
  count    = 2
  domain   = "vpc"
  tags = { Name = "ped-eip-bastion-${count.index == 0 ? "a" : "b"}" }
}

resource "aws_eip_association" "bastion" {
  count         = 2
  instance_id   = aws_instance.bastion[count.index].id
  allocation_id = aws_eip.bastion[count.index].id
}

# --- DMZ TIER: NGINX Reverse Proxy (Graviton nano, one per AZ) ---
# HLD §5.4.1 - t4g.nano (512MB). Upgrade to t4g.micro (1GB) if sustained high CPU/memory.
resource "aws_instance" "dmz" {
  count                  = 2
  ami                    = data.aws_ami.debian.id
  instance_type          = "t4g.nano"
  subnet_id              = aws_subnet.public[count.index].id
  vpc_security_group_ids = [aws_security_group.dmz_sg.id]
  key_name               = var.bastion_key_name
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  root_block_device {
    volume_size = 20
    encrypted   = true
    kms_key_id  = aws_kms_key.main.arn
    volume_type = "gp3"
  }

  metadata_options { http_tokens = "required" } # IMDSv2 enforced

  tags = {
    Name = "ped-dmz-${count.index == 0 ? "a" : "b"}"
    Role = "NGINX"
    Tier = "DMZ"
    AZ   = "eu-west-2${count.index == 0 ? "a" : "b"}"
  }
}

resource "aws_eip" "dmz" {
  count  = 2
  domain = "vpc"
  tags = { Name = "ped-eip-dmz-${count.index == 0 ? "a" : "b"}" }
}

resource "aws_eip_association" "dmz" {
  count         = 2
  instance_id   = aws_instance.dmz[count.index].id
  allocation_id = aws_eip.dmz[count.index].id
}

# --- APP TIER: Drupal 11 (Graviton, 4GB RAM, one per AZ) ---
# HLD §5.4.1 - t4g.medium (4GB RAM). Scale horizontally by adding instances.
resource "aws_instance" "app" {
  count                  = 2
  ami                    = data.aws_ami.debian.id
  instance_type          = "t4g.medium"
  subnet_id              = aws_subnet.public[count.index].id
  vpc_security_group_ids = [aws_security_group.app_sg.id]
  key_name               = var.bastion_key_name
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  root_block_device {
    volume_size = 50
    encrypted   = true
    kms_key_id  = aws_kms_key.main.arn
    volume_type = "gp3"
  }

  metadata_options { http_tokens = "required" } # IMDSv2 enforced

  tags = {
    Name = "ped-app-${count.index == 0 ? "a" : "b"}"
    Role = "Drupal"
    Tier = "APP"
    AZ   = "eu-west-2${count.index == 0 ? "a" : "b"}"
  }
}

resource "aws_eip" "app" {
  count  = 2
  domain = "vpc"
  tags = { Name = "ped-eip-app-${count.index == 0 ? "a" : "b"}" }
}

resource "aws_eip_association" "app" {
  count         = 2
  instance_id   = aws_instance.app[count.index].id
  allocation_id = aws_eip.app[count.index].id
}

# --- DATA LAYER: RDS MariaDB Multi-AZ (HLD §5.4.1 / §5.10.2) ---
resource "aws_db_subnet_group" "main" {
  name       = "ped-rds-subnet-group-${var.environment}"
  subnet_ids = aws_subnet.data[*].id
  tags       = { Name = "ped-rds-subnet-group" }
}

resource "aws_db_instance" "main" {
  identifier                = "ped-mariadb-${var.environment}"
  engine                    = "mariadb"
  engine_version            = "11.4"
  instance_class            = "db.m6g.large" # HLD §5.4.1
  allocated_storage         = 100            # HLD §5.10.3 - initial 100GB, vertical scaling path
  max_allocated_storage     = 500
  storage_type              = "gp3"
  storage_encrypted         = true
  kms_key_id                = aws_kms_key.main.arn
  db_name                   = "ped"
  username                  = "ped_admin"
  password                  = var.db_password
  db_subnet_group_name      = aws_db_subnet_group.main.name
  vpc_security_group_ids    = [aws_security_group.rds_sg.id]
  multi_az                  = true  # Automatic failover to standby AZ (HLD §5.10.2)
  backup_retention_period   = 30    # HLD §6.2 - 30-day automated backup retention
  backup_window             = "02:00-03:00"
  maintenance_window        = "tue:03:00-tue:04:00"
  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "ped-mariadb-${var.environment}-final"
  tags = { Name = "ped-mariadb", Classification = "OFFICIAL-SENSITIVE" }
}

# --- DATA LAYER: ElastiCache Redis Multi-AZ (session storage - HLD §5.4.2) ---
resource "aws_elasticache_subnet_group" "main" {
  name       = "ped-redis-subnet-group-${var.environment}"
  subnet_ids = aws_subnet.data[*].id
}

resource "aws_elasticache_replication_group" "main" {
  replication_group_id       = "ped-redis-${var.environment}"
  description                = "PPE Platform - Drupal session management"
  node_type                  = "cache.t4g.small"
  num_cache_clusters         = 2    # Primary + replica across AZs (HLD §5.10.2)
  automatic_failover_enabled = true
  multi_az_enabled           = true
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  kms_key_id                 = aws_kms_key.main.arn
  subnet_group_name          = aws_elasticache_subnet_group.main.name
  security_group_ids         = [aws_security_group.redis_sg.id]
  tags = { Name = "ped-redis", Classification = "OFFICIAL-SENSITIVE" }
}

# --- DATA LAYER: EFS (shared Drupal media, accessible across AZs - HLD §5.4.1) ---
# Performance mode: generalPurpose (HLD §8 Decision 3 - validate under load)
# Mount targets placed in data subnets; reachable from APP instances via VPC-local routing.
resource "aws_efs_file_system" "main" {
  encrypted        = true
  kms_key_id       = aws_kms_key.main.arn
  performance_mode = "generalPurpose"
  tags = { Name = "ped-efs-${var.environment}", Classification = "OFFICIAL-SENSITIVE" }
}

resource "aws_efs_mount_target" "app" {
  count           = 2
  file_system_id  = aws_efs_file_system.main.id
  subnet_id       = aws_subnet.data[count.index].id
  security_groups = [aws_security_group.efs_sg.id]
}

# --- DATA LAYER: S3 - DSTL Legacy Archive (16,000+ files - HLD §5.6) ---
# Object Lock (Compliance mode) ensures true immutability - no principal can delete
# within retention window (HLD §6.2 Backup Immutability)
resource "aws_s3_bucket" "archive" {
  bucket              = "ped-dstl-archive-${var.environment}-${data.aws_caller_identity.current.account_id}"
  object_lock_enabled = true
  force_destroy       = false
  tags = { Name = "ped-dstl-archive", Classification = "OFFICIAL-SENSITIVE" }
}

resource "aws_s3_bucket_versioning" "archive" {
  bucket = aws_s3_bucket.archive.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_object_lock_configuration" "archive" {
  bucket = aws_s3_bucket.archive.id
  rule {
    default_retention {
      mode = "COMPLIANCE" # Cannot be overridden by root account (HLD §6.2)
      days = 90
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "archive" {
  bucket = aws_s3_bucket.archive.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.main.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "archive" {
  bucket                  = aws_s3_bucket.archive.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- DATA LAYER: S3 - Backups (RDS snapshots, config exports - HLD §6.2) ---
resource "aws_s3_bucket" "backups" {
  bucket              = "ped-backups-${var.environment}-${data.aws_caller_identity.current.account_id}"
  object_lock_enabled = true
  force_destroy       = false
  tags = { Name = "ped-backups", Classification = "OFFICIAL-SENSITIVE" }
}

resource "aws_s3_bucket_versioning" "backups" {
  bucket = aws_s3_bucket.backups.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_object_lock_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id
  rule {
    default_retention {
      mode = "COMPLIANCE"
      days = 90 # HLD §6.2 - 90-day retention for manual snapshots
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.main.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "backups" {
  bucket                  = aws_s3_bucket.backups.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- S3: ACCESS LOGGING BUCKET ---
# Receives server access logs from archive and backup buckets (STRIDE §7.4)
resource "aws_s3_bucket" "access_logs" {
  bucket        = "ped-s3-access-logs-${var.environment}-${data.aws_caller_identity.current.account_id}"
  force_destroy = false
  tags = { Name = "ped-s3-access-logs", Classification = "OFFICIAL-SENSITIVE" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.main.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "access_logs" {
  bucket                  = aws_s3_bucket.access_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_logging" "archive" {
  bucket        = aws_s3_bucket.archive.id
  target_bucket = aws_s3_bucket.access_logs.id
  target_prefix = "archive/"
}

resource "aws_s3_bucket_logging" "backups" {
  bucket        = aws_s3_bucket.backups.id
  target_bucket = aws_s3_bucket.access_logs.id
  target_prefix = "backups/"
}

# --- CLOUDWATCH ALARMS (HLD §6.1 Alerting Strategy) ---
# All alarms notify the ped-alerts SNS topic. Thresholds taken directly from HLD §6.1.

# APP instances: CPU > 80% for 10 minutes
resource "aws_cloudwatch_metric_alarm" "app_cpu_high" {
  count               = 2
  alarm_name          = "ped-app-${count.index == 0 ? "a" : "b"}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300 # 5-minute periods; 2 = 10 minutes total (HLD §6.1)
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "APP instance CPU > 80% for 10 mins - scale or investigate (HLD §6.1)"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  dimensions          = { InstanceId = aws_instance.app[count.index].id }
  tags = { Name = "ped-alarm-app-cpu-${count.index == 0 ? "a" : "b"}" }
}

# DMZ instances: CPU > 80% for 10 minutes (t4g.nano - upgrade to micro if sustained)
resource "aws_cloudwatch_metric_alarm" "dmz_cpu_high" {
  count               = 2
  alarm_name          = "ped-dmz-${count.index == 0 ? "a" : "b"}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "DMZ instance CPU > 80% for 10 mins - consider upgrade to t4g.micro (HLD §5.10.1)"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  dimensions          = { InstanceId = aws_instance.dmz[count.index].id }
  tags = { Name = "ped-alarm-dmz-cpu-${count.index == 0 ? "a" : "b"}" }
}

# RDS: connections > 75% of max (HLD §6.1)
resource "aws_cloudwatch_metric_alarm" "rds_connections_high" {
  alarm_name          = "ped-rds-connections-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = 112 # 75% of db.m6g.large max connections (~150)
  alarm_description   = "RDS connections > 75% of max - investigate connection leaks (HLD §6.1)"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  dimensions          = { DBInstanceIdentifier = aws_db_instance.main.id }
  tags = { Name = "ped-alarm-rds-connections" }
}

# RDS: FreeStorageSpace < 20GB warning
resource "aws_cloudwatch_metric_alarm" "rds_storage_low" {
  alarm_name          = "ped-rds-storage-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 21474836480 # 20GB in bytes
  alarm_description   = "RDS free storage < 20GB - review capacity (HLD §5.10.3)"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  dimensions          = { DBInstanceIdentifier = aws_db_instance.main.id }
  tags = { Name = "ped-alarm-rds-storage" }
}

# RDS: automated backup failure (HLD §6.1 - "Backup Failure: Any failure → Immediate investigation")
resource "aws_cloudwatch_metric_alarm" "rds_backup_failure" {
  alarm_name          = "ped-rds-backup-failure"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "BackupRetentionPeriodStorageUsed"
  namespace           = "AWS/RDS"
  period              = 86400 # Daily
  statistic           = "Minimum"
  threshold           = 1
  alarm_description   = "RDS backup may have failed - immediate investigation required (HLD §6.1)"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  dimensions          = { DBInstanceIdentifier = aws_db_instance.main.id }
  tags = { Name = "ped-alarm-rds-backup" }
}

# ElastiCache Redis: CPU > 80% for 5 minutes
resource "aws_cloudwatch_metric_alarm" "redis_cpu_high" {
  alarm_name          = "ped-redis-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ElastiCache"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Redis CPU > 80% for 5 mins - investigate session load (HLD §6.1)"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  dimensions          = { ReplicationGroupId = aws_elasticache_replication_group.main.id }
  tags = { Name = "ped-alarm-redis-cpu" }
}
