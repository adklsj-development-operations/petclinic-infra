# petclinic-infra

Terraform + Ansible infrastructure for the Spring Petclinic application.
Provisions an EC2 instance on AWS and configures it as a single-node k3s (lightweight Kubernetes) cluster.

Fully reproducible — anyone with AWS credentials can clone this repo and bring up the entire stack from scratch.

## Architecture

```
petclinic-infra (this repo)          spring-petclinic (app repo)
────────────────────────────         ───────────────────────────
bootstrap/  → S3 bucket + DynamoDB   CI  → build → test → push image
Terraform   → EC2 + security group   CD  → kubectl apply to k3s
Ansible     → installs k3s
```

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5.0
- [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/) >= 2.14
- AWS CLI configured (`aws configure`) with `AmazonEC2FullAccess`, `AmazonS3FullAccess`, `AmazonDynamoDBFullAccess`

## First-time setup (from scratch)

### 1. Bootstrap remote state

Creates the S3 bucket and DynamoDB table that store Terraform state. Must be run by everyone setting up a new environment — each user provides a unique prefix to avoid S3 naming conflicts.

```bash
cd bootstrap
terraform init
terraform apply -var="prefix=yourname"
cd ..
```

Note the outputs — you'll need them in the next step:
```
bucket_name    = "yourname-petclinic-tfstate"
dynamodb_table = "yourname-petclinic-tfstate-lock"
```

### 2. Configure the backend

```bash
cp backend.hcl.example backend.hcl
# Edit backend.hcl and replace YOUR_PREFIX with the prefix you used above
```

Then init with the backend config:
```bash
terraform init -backend-config=backend.hcl
```

### 3. Add GitHub Actions secrets

In this repo's Settings → Secrets and variables → Actions:

| Secret | Value |
|---|---|
| `AWS_ACCESS_KEY_ID` | AWS IAM access key |
| `AWS_SECRET_ACCESS_KEY` | AWS IAM secret key |
| `AWS_SESSION_TOKEN` | AWS session token (if using temporary credentials) |
| `TF_STATE_BUCKET` | Bootstrap output: `bucket_name` e.g. `yourname-petclinic-tfstate` |
| `TF_STATE_DYNAMODB_TABLE` | Bootstrap output: `dynamodb_table` e.g. `yourname-petclinic-tfstate-lock` |

These last two tell the CI workflow which S3 bucket and DynamoDB table to use for remote state — without them the workflow can't init Terraform.

### 4. Provision infrastructure

```bash
terraform apply
```

Terraform will:
- Generate an RSA key pair and register it with AWS
- Create a security group (ports 22, 6443, 30080)
- Launch a `t3.small` Ubuntu 22.04 EC2 instance
- Store all state remotely in S3 — safe for anyone to run

### 5. Copy outputs to the app repo

In `spring-petclinic` → Settings → Secrets and variables → Actions, add:

| Secret | Command to get value |
|---|---|
| `EC2_PUBLIC_IP` | `terraform output public_ip` |
| `EC2_SSH_PRIVATE_KEY` | `terraform output -raw private_key_pem` |

### 6. Run Ansible to install k3s
Write key to file — terraform -raw strips the trailing newline which breaks PEM

```bash
terraform output -raw private_key_pem > /tmp/petclinic.pem && echo "" >> /tmp/petclinic.pem
chmod 600 /tmp/petclinic.pem

ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook ansible/site.yml \
  -i "$(terraform output -raw public_ip)," \
  --private-key /tmp/petclinic.pem \
  -u ubuntu
```

After this the instance is a ready k3s node. The app repo's CD workflow handles all future deployments automatically on every push to `main`.

## CI/CD (infra.yml)

Triggered on push to `main` or manually via workflow_dispatch.

| Event | What runs |
|---|---|
| Pull request | `terraform plan` only — shows what will change |
| Push to `main` | `terraform apply` → Ansible configures k3s |

## Variables

Defined in `variables.tf`:

| Variable | Default | Description |
|---|---|---|
| `region` | `us-east-1` | AWS region |
| `instance_type` | `t3.small` | EC2 instance type |
| `ami_id` | Ubuntu 22.04 (us-east-1) | AMI — update if changing region |

To override:
```bash
terraform apply -var="region=eu-west-1" -var="ami_id=ami-xxxxxxxx"
```

## Outputs

| Output | Description |
|---|---|
| `public_ip` | EC2 public IP |
| `app_url` | App URL via NodePort — `http://<ip>:30080` |
| `private_key_pem` | SSH private key (sensitive) |

## Tearing down

```bash
terraform destroy  
cd bootstrap
terraform destroy  
```

## Important

- State is stored remotely in S3 — no local `terraform.tfstate` needed
- Bootstrap state is excluded from git — every new environment runs bootstrap independently against their own AWS account
- If the instance is destroyed and recreated, update `EC2_PUBLIC_IP` and `EC2_SSH_PRIVATE_KEY` in the app repo secrets
