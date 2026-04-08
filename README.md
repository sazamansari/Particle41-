# SimpleTimeService — Particle41 DevOps Challenge

> ⚠️ **Billing Notice:** Deploying this infrastructure creates real AWS resources that incur costs. Make sure you run `terraform destroy` when you are done to avoid unexpected charges.

---

## What Is This?

This repo is my submission for the Particle41 DevOps Team Challenge. The goal was to build a minimal web service, containerize it, and deploy it to the cloud in a production-style way using Terraform — with proper networking, a load balancer, and a CI/CD pipeline to tie it all together.

The application itself (`SimpleTimeService`) is intentionally tiny. It's a Node.js HTTP server with a single endpoint that returns the current timestamp and the caller's IP address as JSON. The interesting part is everything around it — the infrastructure, the container setup, and the automation.

---

## The Application

**Endpoint:** `GET /`

**Response:**
```json
{
  "timestamp": "2026-04-08T06:45:00.000Z",
  "ip": "203.0.113.42"
}
```

The IP is read from the `X-Forwarded-For` header, which means it correctly returns the real client IP even when the request comes through an ALB. If that header isn't present, it falls back to the socket's remote address.

The container image is publicly available on DockerHub:
```
docker pull shadab1995/particle41devopschallenge:latest
```

You can run it locally with:
```bash
docker run -p 3000:3000 shadab1995/particle41devopschallenge:latest
curl http://localhost:3000
```

---

## Repository Structure

```
.
├── server.js                        # Application source
├── package.json
├── dockerfile                       # Container build definition
├── .dockerignore
├── .gitignore
├── .github/
│   └── workflows/
│       └── deploy.yml               # CI/CD pipeline (GitHub Actions)
└── terraform/
    ├── provider.tf                  # AWS provider config
    ├── vpc.tf                       # VPC, subnets, IGW, routing
    ├── alb.tf                       # Load balancer, target group, listener
    ├── ecs.tf                       # ECS cluster, task definition, service
    └── outputs.tf                   # Prints the ALB URL after apply
```

---

## Architecture & Why I Chose It

![AWS Architecture](docs/architecture.png)

I went with **AWS ECS Fargate** behind an **Application Load Balancer**, all inside a custom VPC.

**Why Fargate over EKS or a plain EC2?**
For a stateless microservice this small, Kubernetes would add significant operational overhead with very little benefit. Fargate gives you the container-native deployment model without having to manage nodes, autoscaling groups, or a control plane. It's the right-sized tool for this job — you define the task, and AWS runs it.

**Why an ALB instead of a direct NAT or API Gateway?**
The ALB acts as the single public entry point. It handles health checks, can route to multiple tasks if you scale out, and sits naturally in the public subnets while keeping the compute layer separated. The ECS security group (`ecs-sg`) only accepts traffic on port 3000 sourced from the ALB security group (`alb-sg`) — the containers are not reachable directly from the internet.

### Network Layout

| Resource | CIDR / Detail |
|---|---|
| VPC | `10.0.0.0/16` |
| Public Subnet A (`ap-south-1a`) | `10.0.1.0/24` — ALB lives here |
| Public Subnet B (`ap-south-1b`) | `10.0.3.0/24` — ALB spans both AZs |
| Private Subnet (`ap-south-1a`) | `10.0.2.0/24` — reserved for future hardening |

**Traffic flow:**
```
Internet → Internet Gateway → ALB (port 80) → ECS Fargate Task (port 3000)
```

---

## Prerequisites

You'll need the following tools installed before deploying anything.

| Tool | Why You Need It | Install |
|---|---|---|
| Terraform `>= 1.0` | Provisions all AWS infrastructure | [terraform.io/downloads](https://developer.hashicorp.com/terraform/install) |
| AWS CLI `v2` | Configures your credentials locally | [AWS CLI install guide](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) |
| Docker | To build/test the image locally (optional) | [docs.docker.com](https://docs.docker.com/get-docker/) |
| Git | Cloning the repo | [git-scm.com](https://git-scm.com/downloads) |

You'll also need an **AWS account** and an IAM user with permissions for: EC2, VPC, ECS, ELBv2.

---

## Configuring AWS Credentials

> ⚠️ Never commit credentials to this repository. The `.gitignore` already excludes `.tfstate` and `.terraform/`. Keep your keys out of your code.

**Option 1 — AWS CLI (quickest for local use)**

```bash
aws configure
```

You'll be prompted for:
```
AWS Access Key ID:     <your access key>
AWS Secret Access Key: <your secret key>
Default region name:   ap-south-1
Default output format: json
```

**Option 2 — Environment variables**

```bash
export AWS_ACCESS_KEY_ID="your_access_key"
export AWS_SECRET_ACCESS_KEY="your_secret_key"
export AWS_DEFAULT_REGION="ap-south-1"
```

Once configured, verify it's working:
```bash
aws sts get-caller-identity
```

You should see your account ID and IAM user ARN returned. If that works, Terraform will pick up the same credentials automatically.

---

## Deploying the Infrastructure

Everything runs from the `terraform/` directory. These two commands are all you need:

**Step 1 — Initialise**

Downloads the AWS provider and sets up the working directory.

```bash
cd terraform
terraform init
```

**Step 2 — Preview**

See exactly what will be created before anything touches your account. Read through the plan output — you should see 17 resources.

```bash
terraform plan
```

**Step 3 — Deploy**

```bash
terraform apply
```

Type `yes` when prompted. The full apply takes around 3–5 minutes. The ALB takes the longest to provision.

**Step 4 — Access the application**

Once apply completes, the ALB DNS name is printed in the output:

```bash
terraform output alb_url
```

Open it in a browser or test it directly:

```bash
curl http://<alb_url>
```

You should get back:
```json
{
  "timestamp": "2026-04-08T06:45:00.000Z",
  "ip": "your.ip.address.here"
}
```

**Step 5 — Tear it down (important!)**

When you're finished, destroy everything to stop incurring AWS charges:

```bash
terraform destroy
```

Type `yes` to confirm. This removes all 17 resources created during apply.

---

## CI/CD Pipeline (Extra Credit)

The `deploy.yml` workflow in `.github/workflows/` automates the full build and deploy cycle on every push to `main`.

![CI/CD Pipeline](docs/cicd.png)

**What it does, in order:**

1. Checks out the code
2. Builds the Docker image
3. Authenticates to DockerHub and pushes the image
4. Configures AWS credentials from GitHub secrets
5. Runs `terraform init`
6. Runs `terraform validate` (catches config errors before touching AWS)
7. Runs `terraform apply -auto-approve`

**Setting it up in your fork:**

Go to **Settings → Secrets and variables → Actions** in your GitHub repo and add these four secrets:

| Secret | What to put in it |
|---|---|
| `DOCKER_USER` | Your DockerHub username |
| `DOCKER_PASS` | Your DockerHub password or an access token |
| `AWS_ACCESS_KEY_ID` | Your IAM access key |
| `AWS_SECRET_ACCESS_KEY` | Your IAM secret access key |

Once those are in place, pushing to `main` triggers the full pipeline — no manual deployment steps needed.

---

## Running the App Locally (Without Docker)

```bash
# Install dependencies
npm install

# Start the server
npm start

# Test it
curl http://localhost:3000
```

The server starts on port 3000 by default.

---

## Container Details

The Dockerfile is built on `node:alpine` for a minimal image footprint. It also runs as a non-root user (`appuser`) — which is a hard requirement from the challenge spec and a sensible security practice regardless.

The `.dockerignore` excludes `node_modules`, `.git`, and a few other files to keep the build context clean and the final image lean.

---

## What I'd Add With More Time

- **Remote Terraform state** — An S3 backend with DynamoDB locking so the state doesn't live on a local machine. This is important when multiple people (or CI/CD runners) need to run Terraform against the same infrastructure.
- **NAT Gateway + private subnet for ECS** — Moving the Fargate tasks into the private subnet with a NAT Gateway for outbound access. Currently tasks run in public subnets to simplify image pulling from DockerHub.
- **ECS Execution IAM Role** — Adds the proper permissions for Fargate to pull images from ECR and write logs to CloudWatch.
- **CloudWatch logging** — Pipe container stdout/stderr to a log group so you can actually see what's happening at runtime.
- **Auto Scaling** — Scale the ECS service up and down based on CPU/memory usage instead of a fixed `desired_count = 1`.

---

## Author

**Md Shadab Azam Ansari**  
Cloud & DevOps Engineer
