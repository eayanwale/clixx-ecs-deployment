# stack-ecs-clixx

Terraform stack that runs **CliXX Retail** (a WordPress application) as a containerized service on **Amazon ECS with EC2 capacity**. It provisions its own VPC, an ALB fronting an ECS service backed by an EC2 Auto Scaling Group (ECS-optimized AMI, bridge networking), and an RDS instance restored from a shared snapshot. A Jenkins pipeline (`Jenkinsfile`) drives `init`/`plan`/`apply`/`destroy`, runs an AI source-code audit step before applying, and posts status to Slack.

This directory is a standalone ECS deployment — it does not include the classic EC2/Auto Scaling Group WordPress tier (that lives in the separate `stack-aut-clixx` project).

## Architecture

```
                                Internet
                                    │
                                    ▼
                        ecs-lb (ALB, :80 → :443 redirect, :443)
                        ecs.clixx.example.com
                                    │
                          Target Group ecs-tg (port 80)
                                    │
                     ECS Service "clixx" on ECS capacity provider
                   (EC2 ASG "ecs-asg", 1-3 instances, bridge mode,
                    container from ECR, dynamic host port mapping)
                                    │
                                    ▼
                       RDS clixx-restored-ecs (db.m5.large)
                    restored from snapshot clixx-snapshot-has-user

        Bastion host (public subnet) ── SSH access into the private subnets
```

CloudWatch alarms (CPU/memory/disk on the ECS ASG) and a dashboard feed an SNS topic that emails the admins in `var.admin_emails`.

## Resources

| Area | File | Notes |
|---|---|---|
| Networking | [vpc.tf](vpc.tf) | VPC (`20.1.0.0/16`), 2 public + 2 private subnets across `us-east-1a`/`b`, IGW, one NAT gateway per AZ, public/private route tables, S3 gateway endpoint. |
| Security groups | [security.tf](security.tf) | `clixx-sg` (ECS container instances — SSH from the VPC CIDR, HTTP + the ECS dynamic port range `32768-65535` from `alb-sg`), `alb-sg` (public `:80`/`:443`), `bastion-sg` (SSH open to `0.0.0.0/0`), `db-sg` (`3306` from `clixx-sg` and `bastion-sg` only). |
| Bastion | [ec2.tf](ec2.tf) | Public-subnet `t3.micro` (hardcoded AMI) for SSH access into the private subnets — also defines the ALB, target group, and HTTP/HTTPS listeners. |
| ECS | [ecs.tf](ecs.tf) | `ecs_instance_role`/`ecs_instance_profile` (ECS-for-EC2, CloudWatch Agent, SSM policies), ECS cluster, capacity provider tied to `ecs-asg`, task definition (bridge networking, container from `clixx-repository:${var.ecr_image_tag}`, WordPress DB env vars, `WP_HOME`/`WP_SITEURL` hardcoded to the ECS URL), and the service (spread placement by AZ then instance). |
| Database | [rds.tf](rds.tf) | `clixx-restored-ecs` (`db.m5.large`), restored from the most recent `clixx-snapshot-has-user` snapshot, in its own DB subnet group, not publicly accessible. |
| DNS | [route53.tf](route53.tf) | `ecs.clixx.example.com` alias record pointing at `ecs-lb`. |
| Monitoring | [cloudwatch.tf](cloudwatch.tf), [sns.tf](sns.tf) | CPU/memory/disk alarms on the ECS ASG, a `clixx-esg-dashboard` dashboard, and an SNS topic (`clixx-ecs-warnings`) emailing `var.admin_emails`. |
| Data sources | [data.tf](data.tf) | SSM parameters (DB password, org name, role name, git repo URL), the ECS-optimized AMI, the cross-account ECR repo, the Route 53 zone, and the running ECS instances (for the private-IP output). |
| Config | [vars.tf](vars.tf), [locals.tf](locals.tf), [provider.tf](provider.tf), [versions.tf](versions.tf) | Variables/defaults, the two AWS provider configs (default `stackprog-dev` profile plus an `aws.ecs-repo-account` alias on `stackprog-aut` for the cross-account ECR lookup), and the S3 remote-state backend. |

## Deploying

### Via Jenkins (primary path)

The [Jenkinsfile](Jenkinsfile) runs against this directory, parameterized by `ACTION` (`apply` or `destroy`):

1. **AI Source Code Audit** (apply only) — an unattended Claude Code agent (prompt in [ai-source-audit-prompt.txt](ai-source-audit-prompt.txt)) scans for hardcoded secrets and fixes minor `.tf` syntax issues, then commits/tags/opens a PR if it changed anything; stops without proceeding if secrets are found.
2. **Terraform Init** — `terraform init -upgrade`, Slack notification.
3. **Terraform Plan** — `terraform plan -out=tfplan` (`-destroy` when tearing down).
4. **Terraform Apply** — applies the plan, posts the live `clixx_ecs_url` output to Slack.
5. **Terraform Destroy** — first targets `aws_ecs_service.clixx`, `aws_ecs_cluster_capacity_providers.clixx-ccp`, and `aws_ecs_capacity_provider.clixx-cp` to unwind the ECS/ASG dependency cleanly, then runs a full `terraform destroy`.

Slack notifications (start, deploy complete, destroy complete, and pass/fail) post to `#stackjenkins`.

### Manually

```bash
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

Requires the `stackprog-dev` AWS CLI profile (and `stackprog-aut` for the cross-account ECR data source) configured locally.

## Outputs

| Output | Description |
|---|---|
| `clixx_ecs_url` | Public URL for the app (`https://ecs.clixx.example.com`). |
| `bastion_ip` | Public IP of the bastion host. |
| `clixx_ecs_priv_ips` | Private IPs of the running ECS container instances. |

## Prerequisites

Provisioned outside this stack, and expected to already exist:

- An IAM role Terraform assumes to deploy (`ROLE_NAME`, read from SSM `/stack/role`).
- A custom ECS-optimized AMI named `ami-ecs-stack-*`, owned by `var.ami_owner_account_id`.
- The `clixx-repository` ECR repo populated with the app image, in the account behind the `aws.ecs-repo-account` provider alias (`stackprog-aut`).
- A DB snapshot named `clixx-snapshot-has-user` in the target account/region — `clixx-restored-ecs` restores from it.
- SSM parameters: `/stack/orgname`, `/stack/role`, `/stack/clixx/repo`, `/stack/clixx/db_password` (SecureString).
- An S3 bucket for remote state (`enoch-tf-state-bucket`, see [versions.tf](versions.tf)).
- A Route 53 hosted zone (`clixx.example.com`).
- An ACM certificate covering `*.clixx.example.com` in `us-east-1` — its ARN is hardcoded in [ec2.tf](ec2.tf) rather than looked up, so it's tied to this specific account.
- An EC2 key pair (`var.key_name`, default `dev-servers`) for bastion/instance SSH access.

## Known caveats

- `skip_final_snapshot = true` on the RDS instance means a `terraform destroy` throws away the live database without a final snapshot — fine since the source snapshot is the durable copy, but any writes since the last restore are lost.
- `force_delete = true` on both the ECS ASG and the ECS service is convenient for iterating in dev but should not be carried into a production stack as-is.
- `bastion-sg` allows SSH from `0.0.0.0/0`, unlike the rest of the stack's least-privilege security groups — worth tightening to a known CIDR.
- The bastion AMI ID and the HTTPS listener's ACM certificate ARN are hardcoded rather than looked up via data sources, so this stack isn't portable to another account/region without editing [ec2.tf](ec2.tf) directly.
- The commented-out root-domain Route 53 record in [route53.tf](route53.tf) suggests `clixx.example.com` (no subdomain) was once meant to point here too; currently only `ecs.clixx.example.com` is wired up.
