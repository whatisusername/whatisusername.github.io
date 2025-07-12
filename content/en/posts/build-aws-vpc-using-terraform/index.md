---
title: 'Build AWS VPC Using Terraform'
date: 2025-07-12T22:56:30+08:00
draft: false
description:
isStarred: false
---

- OS: Windows 11
- Terraform version: 1.10.5

After reading the previous article, you should now have a basic understanding of Terraform. In this post, we'll reinforce that knowledge through a hands-on example.
To avoid jumping into overly complex tasks too soon, this article will guide you step by step in using basic `resource` blocks to create an AWS VPC. In the next article, we'll refactor the setup using Modules.
VPC (Virtual Private Cloud) is a networking service provided by AWS that allows you to create an isolated network environment in the cloud. For readers interested in a deeper dive, you can refer to the [official documentation](https://docs.aws.amazon.com/vpc/latest/userguide/what-is-amazon-vpc.html).

The main goal of this article is to use Terraform to create the following resources:

- 1 VPC
- 1 Public Subnet
- 1 Private Subnet
- 2 Route Tables
- 2 Network ACLs
- 1 Internet Gateway

# Prerequisites

Before we start writing Terraform configurations, we need to set up the local environment. This guide focuses on the Windows operating system.

## Install Terraform

If you're not using Windows, refer to the [official Install Terraform guide](https://developer.hashicorp.com/terraform/install).

First, open PowerShell and run the following command to create a folder for installing Terraform:

```powershell
mkdir "$env:LOCALAPPDATA\Programs\Terraform\bin"
```

Download the appropriate version of Terraform for your CPU architecture. In this example, we’ll download the [Windows AMD64 v1.10.5 Terraform zip file](https://releases.hashicorp.com/terraform/1.10.5/terraform_1.10.5_windows_amd64.zip), then extract it to the folder you just created.

After extracting the files, go to `User Environment Variables`, and add the following path to your `Path` variable:

```
%LOCALAPPDATA%\Programs\Terraform\bin
```

Once that’s done, restart PowerShell and run the following command to verify the installation:

```powershell
terraform -version
```

If the output shows something like Terraform v1.10.5 on windows_amd64, the installation was successful.

## AWS Setup

### Install AWS CLI

Follow the [official documentation](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) to install the AWS CLI according to your operating system.

### Configure AWS Profile

The config and credentials files are stored under `$env:UserProfile\.aws`. To set up a default profile, run the following command:

```powershell
aws configure
```

Then enter the following information when prompted:

1. Access Key
2. Secret Access Key
3. Default Region (e.g., ap-northeast-1)
4. Output Format (e.g, json)

# HCL

According to the [official recommendation](https://www.notion.so/Terraform-AWS-VPC-21302d46621680089625ffb854fef1b2?pvs=21), we'll start by creating the following files: main.tf, variables.tf, outputs.tf, terraform.tf, providers.tf, backend.tf, and locals.tf. After creating these files, the project structure should look like this:

```
terraform-demo/
├── backend.tf      # Backend configuration
├── locals.tf       # Local variable definitions
├── main.tf         # Main resource definitions
├── outputs.tf      # Output values
├── providers.tf    # Provider configurations
├── terraform.tf    # Core Terraform settings (version and required providers)
└── variables.tf    # Input variable declarations
```

## Define Terraform and Provider Versions

Before defining resources such as the VPC, we need to specify the required Terraform version and the provider to use. In this example, we’ll use Terraform version 1.0 or later, along with AWS Provider version 6.3.X:

```hcl
# terraform.tf
terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.3.0"
    }
  }
}
```

## Use Local Backend

By default, Terraform uses the local backend, which stores the state file in the project directory. However, we’ll define it explicitly here to make it clear which part to modify later when switching to a remote backend:

```hcl
# backend.tf
terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}
```

>💡 If you omit the backend block, Terraform will still default to using a local state file. Therefore, this configuration is not strictly required, but it helps make the structure more explicit.

## VPC

Let’s start with the most basic resource: the VPC. First, define the VPC name prefix and a CIDR block in the variables.tf file:

```hcl
# variables.tf
variable "name" {
  description = "Name of the VPC"
  type        = string
  default     = "demo"
}
```

Next, in locals.tf, construct the full VPC name and select a single Availability Zone to simplify the architecture. For this example, we’ll use just one AZ:

```hcl
# locals.tf
data "aws_availability_zones" "available" {}

locals {
  vpc_name = "${var.name}-vpc"
  azs      = slice(data.aws_availability_zones.available.names, 0, 1)
}
```

Finally, define a VPC in main.tf, and enable DNS support:

```hcl
# main.tf
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = local.vpc_name
  }
}
```

## Subnet

Next, we’ll create one Public Subnet and one Private Subnet for the VPC.
To avoid overlapping CIDR blocks, we’ll use Terraform’s cidrsubnet function to automatically calculate the CIDR for each subnet.

Add the following to locals.tf to compute the CIDR blocks for the public and private subnets:

```hcl
# locals.tf
locals {
  public_subnets  = [for k, v in local.azs : cidrsubnet(aws_vpc.main.cidr_block, 4, k)]
  private_subnets = [for k, v in local.azs : cidrsubnet(aws_vpc.main.cidr_block, 4, k + 8)]
}
```

>💡 The cidrsubnet(base, newbits, netnum) function is used to split an existing CIDR block into smaller subnets.
>   In this case, we divide a /16 block into multiple /20 subnets (since 4 = 20 - 16), and use different netnum values to avoid overlap.

Next, define the Public and Private Subnets in main.tf:

```hcl
# main.tf
resource "aws_subnet" "public" {
  count = length(local.azs)

  availability_zone       = element(local.azs, count.index)
  cidr_block              = element(local.public_subnets, count.index)
  map_public_ip_on_launch = true
  vpc_id                  = aws_vpc.main.id

  tags = {
    Name = format("${var.name}-subnet-public%s-%s", count.index + 1, element(local.azs, count.index))
    Type = "Public"
  }
}

resource "aws_subnet" "private" {
  count = length(local.azs)

  availability_zone = element(local.azs, count.index)
  cidr_block        = element(local.private_subnets, count.index)
  vpc_id            = aws_vpc.main.id

  tags = {
    Name = format("${var.name}-subnet-private%s-%s", count.index + 1, element(local.azs, count.index))
    Type = "Private"
  }
}
```

## Internet Gateway

Since we’ve created a Public Subnet, we now need to allow it to connect to the Internet.
To do this, we’ll attach an Internet Gateway to the VPC.

```hcl
# main.tf
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.name}-igw"
  }
}
```

>💡 An Internet Gateway acts as the gateway between a VPC and the public Internet. A subnet is only considered truly "public" if it's properly routed to the Internet Gateway and has map_public_ip_on_launch enabled.

## Route Table

Next, we’ll configure a Route Table to enable the subnets to communicate externally.
The Public Subnet needs a route through the Internet Gateway to access the Internet, while the Private Subnet remains isolated for internal communication only.

First, create a Route Table for the Public Subnet and add a route that directs outbound traffic through the IGW:

```hcl
# main.tf
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.name}-rtb-public"
  }
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = element(aws_subnet.public[*].id, count.index)
  route_table_id = aws_route_table.public.id
}

resource "aws_route" "public_internet_gateway" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id

  timeouts {
    create = "5m"
  }
}
```

The Private Subnet doesn’t need to connect to the Internet Gateway, but it should still be able to communicate with other subnets within the VPC.

```hcl
# main.tf
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.name}-rtb-private"
  }
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = element(aws_subnet.private[*].id, count.index)
  route_table_id = aws_route_table.private.id
}
```

## NACL

Next, we’ll create corresponding Network ACLs (NACLs) for both the Public and Private Subnets.
NACLs are subnet-level network access control mechanisms that allow you to define rules for allowing or denying traffic.

For now, we’ll allow all traffic to simplify testing and development. You can tighten the rules later based on your security requirements.

Here is the NACL configuration for the Public Subnet:

```hcl
# main.tf
resource "aws_network_acl" "public" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = aws_subnet.public[*].id

  tags = {
    Name = "${var.name}-nacl-public"
  }
}

resource "aws_network_acl_rule" "public_inbound" {
  network_acl_id = aws_network_acl.public.id

  egress      = false
  rule_number = 100
  rule_action = "allow"
  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_block  = "0.0.0.0/0"
}

resource "aws_network_acl_rule" "public_outbound" {
  network_acl_id = aws_network_acl.public.id

  egress      = true
  rule_number = 100
  rule_action = "allow"
  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_block  = "0.0.0.0/0"
}
```

And for the Private Subnet:

```hcl
# main.tf
resource "aws_network_acl" "private" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name = "${var.name}-nacl-private"
  }
}

resource "aws_network_acl_rule" "private_inbound" {
  network_acl_id = aws_network_acl.private.id

  egress      = false
  rule_number = 100
  rule_action = "allow"
  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_block  = "0.0.0.0/0"
}

resource "aws_network_acl_rule" "private_outbound" {
  network_acl_id = aws_network_acl.private.id

  egress      = true
  rule_number = 100
  rule_action = "allow"
  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_block  = "0.0.0.0/0"
}
```

## Deployment

Once all the configurations above are complete, you're ready to deploy.

### Format the Code

First, format the .tf files to ensure consistent and readable syntax:

```powershell
terraform fmt
```

### Initialize the Project

Initialize the Terraform project, download the required providers, and set up the working directory:

```powershell
terraform init
```

After initialization, you’ll notice a `.terraform/` directory and a `.terraform.lock.hcl` file are created:

- `.terraform/`: Contains provider binaries, Terraform version information, and backend initialization metadata.
- `.terraform.lock.hcl`: Records the exact versions of the providers used to ensure consistent results across teams and future runs, avoiding unexpected changes due to version upgrades.

### Apply the Configuration

Now you can deploy the defined resources to AWS:

```powershell
terraform apply
```

Type `yes` when prompted to begin execution.
Once completed, you’ll see the VPC, subnets, NACLs, and other resources created in your AWS account. A `terraform.tfstate` file will also appear in the project root, recording the current state of all resources managed by Terraform.

### Destroy the Resources

If the resources were only for testing or if you want to clean up the environment, you can destroy all Terraform-managed resources with the following command:

```powershell
terraform destroy
```

Just like apply, type `yes` to confirm and begin the destruction process.

After destruction, the `terraform.tfstate` file will show an empty resources array. You’ll also find a `terraform.tfstate.backup` file, which holds the last known successful state.
