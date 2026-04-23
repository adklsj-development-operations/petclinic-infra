# petclinic-infra

Terraform + Ansible infrastructure for the Spring Petclinic application.
Provisions an EC2 instance on AWS and configures it as a single-node k3s (lightweight Kubernetes) cluster.

## Architecture

```
petclinic-infra (this repo)          spring-petclinic (app repo)
────────────────────────────         ───────────────────────────
Terraform → EC2 + security group     CI  → build → test → push image
Ansible   → installs k3s             CD  → kubectl apply to k3s
```

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5.0
- [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/) >= 2.14
- AWS credentials with `AmazonEC2FullAccess`

## First-time setup

### 1. Add GitHub Actions secrets

In this repo's Settings → Secrets and variables → Actions:

| Secret | Value |
|---|---|
| `AWS_ACCESS_KEY_ID` | AWS IAM access key |
| `AWS_SECRET_ACCESS_KEY` | AWS IAM secret key |

### 2. Provision infrastructure locally

```bash
terraform init
terraform apply
```

Terraform will:
- Generate an RSA key pair and register it with AWS
- Create a security group (ports 22, 6443, 30080)
- Launch a `t3.small` Ubuntu 22.04 EC2 instance

### 3. Grab outputs for the app repo

copy EC2_PUBLIC_IP and EC2_SSH_PRIVATE_KEY secret to spring-petclinic repository

```bash
terraform output public_ip
terraform output -raw private_key_pem
```

### 4. Run Ansible to install k3s
Write key to file — terraform -raw strips the trailing newline which breaks PEM

```bash
terraform output -raw private_key_pem > /tmp/petclinic.pem && echo "" >> /tmp/petclinic.pem
chmod 600 /tmp/petclinic.pem

ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook ansible/site.yml \
  -i "$(terraform output -raw public_ip)," \
  --private-key /tmp/petclinic.pem \
  -u ubuntu
```

After this the instance is a ready k3s node. The app repo's CD workflow handles all future deployments.

## CI/CD (infra.yml)

Triggered on push to `main` or manually via workflow_dispatch.

| Event          | What runs                                      |
|----------------|------------------------------------------------|
| Pull request   | `terraform plan` only — shows what will change |
| Push to `main` | `terraform apply` → Ansible configures k3s     |

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

## Important

- **Do not commit `terraform.tfstate`** — it contains the private key in plaintext
- `.gitignore` excludes `terraform.tfstate*` and `.terraform/`
- If the instance is destroyed and recreated, update `EC2_PUBLIC_IP` and `EC2_SSH_PRIVATE_KEY` in the app repo secrets
