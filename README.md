# petclinic-infra

Terraform + Ansible infrastructure for the Spring Petclinic application.
Provisions an EC2 instance on AWS and configures it with Docker and a monitoring stack (Prometheus + Grafana).

## Architecture

```
petclinic-infra (this repo)          spring-petclinic (app repo)
────────────────────────────         ───────────────────────────
Terraform   → EC2 + security group   CI → build → test → push image
Ansible     → Docker + monitoring    CD → docker pull + docker run
(run once locally)
```

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5.0
- [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/) >= 2.14
- AWS CLI configured (`aws configure`) with `AmazonEC2FullAccess`

## Setup

### 1. Provision infrastructure

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars if needed
terraform init
terraform apply
```

Terraform will:
- Generate an RSA key pair and register it with AWS
- Create a security group (ports 22, 8080, 3000, 9090)
- Launch a `t3.small` Ubuntu 22.04 EC2 instance

### 2. Add secrets to the app repo

In `spring-petclinic` → Settings → Secrets and variables → Actions:

| Secret                | Command                                 |
|-----------------------|-----------------------------------------|
| `EC2_PUBLIC_IP`       | `terraform output public_ip`            |
| `EC2_SSH_PRIVATE_KEY` | `terraform output -raw private_key_pem` |
| `SLACK_WEBHOOK_URL`   | See below                               |

#### Getting a Slack webhook URL

1. Go to [api.slack.com/apps](https://api.slack.com/apps) → **Create New App** → **From scratch**
2. Name it `petclinic`, pick your workspace
3. **Incoming Webhooks** → toggle **On**
4. **Add New Webhook to Workspace** → pick a channel (e.g. `#deployments`)
5. Copy the URL: `https://hooks.slack.com/services/T.../B.../...`

### 3. Run Ansible

```bash
terraform output -raw private_key_pem > /tmp/petclinic.pem && echo "" >> /tmp/petclinic.pem
chmod 600 /tmp/petclinic.pem

cp ansible/vars.yml.example ansible/vars.yml

ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook ansible/site.yml \
  -i "$(terraform output -raw public_ip)," \
  --private-key /tmp/petclinic.pem \
  -u ubuntu \
  -e @ansible/vars.yml
```

After this the server is up:

| Service    | URL                                |
|------------|------------------------------------|
| App        | `http://<ip>:8080`                 |
| Grafana    | `http://<ip>:3000` (admin / admin) |
| Prometheus | `http://<ip>:9090`                 |

The `spring-petclinic` CD workflow handles all future deployments on every push to `main`.

## Variables

| Variable        | Default                  | Description                     |
|-----------------|--------------------------|---------------------------------|
| `region`        | `us-east-1`              | AWS region                      |
| `instance_type` | `t3.small`               | EC2 instance type               |
| `ami_id`        | Ubuntu 22.04 (us-east-1) | AMI — update if changing region |

## Outputs

| Output            | Description                 |
|-------------------|-----------------------------|
| `public_ip`       | EC2 public IP               |
| `app_url`         | `http://<ip>:8080`          |
| `private_key_pem` | SSH private key (sensitive) |

## Tearing down

```bash
terraform destroy
```

## Important

- `terraform.tfstate` is gitignored — it contains the private key in plaintext
- Never commit `terraform.tfvars` or the Slack webhook URL
- If the instance is destroyed and recreated, update `EC2_PUBLIC_IP` and `EC2_SSH_PRIVATE_KEY` in the app repo secrets 
