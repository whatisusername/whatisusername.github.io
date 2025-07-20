---
title: 'Refactoring AWS VPC With Terraform Module'
date: 2025-07-20T18:21:53+08:00
draft: false
description:
isStarred: false
---

- OS: Windows 11
- PowerShell version: 5.1
- Terraform version: 1.10.5

Modularization allows us to encapsulate infrastructure into reusable units, improving maintainability and consistency.

This article builds upon the previous post, "Build AWS VPC Using Terraform". In that post, we manually wrote multiple resource blocks to provision the VPC and its related components. This time, we’ll refactor the setup using the community-maintained Terraform AWS modules.

Why choose this module?
Every developer writes HCL in their own style. Unless a company maintains a standardized set of modules, delegating tasks to contractors or different teams often leads to inconsistent code that’s difficult to integrate or debug. This module is not only stable and mature but also highly flexible and well-documented, making it my preferred choice during development.

# Git Clone VPC Module

I personally prefer cloning the module's source code locally to easily explore its examples and parameter usage.

```powershell
git clone https://github.com/terraform-aws-modules/terraform-aws-vpc.git
```

The repository contains many files, but we can focus on the key ones listed below. These files provide a great reference for how to write configurations, and studying examples is an excellent way to learn.

```
terraform-aws-vpc/
├── examples/       # Usage examples
├── modules/        # Submodules used within the VPC module
├── main.tf         # Resource definitions inside the module
├── outputs.tf      # Output variable definitions
├── variables.tf    # Configurable input variables
└── versions.tf     # Terraform and provider version settings
```

# Refactoring

Below is the file structure from the previous post. We'll start refactoring from main.tf into a modular version:

```
terraform-demo/
├── backend.tf      # Backend configuration
├── locals.tf       # Local variable definitions
├── main.tf         # Main resource definitions
├── outputs.tf      # Output variable definitions
├── providers.tf    # Provider configuration
├── terraform.tf    # Terraform core settings (required version and providers)
└── variables.tf    # Input variable declarations
```

## VPC

We can compare the implementation of `aws_vpc` in the official module with the manual version from the previous post. You'll notice that the module has already encapsulated various resources for us—so all we need to do is provide the appropriate input variables.

For example:

- `cidr_block` supports logic for IPAM, but since we don't need it in this case, we can simply provide a fixed CIDR value.
- `enable_dns_hostnames` and `enable_dns_support` are both set to `true` by default in the module (refer to the module's variables.tf), so we don’t need to specify them manually.
- The `name` variable is commonly used and applied to resource tags within the module. If we want to customize the name—for instance, to avoid a `-vpc` suffix—we can override the Name tag using `vpc_tags`. This involves the use of the [merge function](https://developer.hashicorp.com/terraform/language/functions/merge).

Below is the refactored `aws_vpc` block. At the time of writing, the module version is `v6.0.1`:

```hcl
# main.tf
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0.0"

  # VPC
  name = var.name
  cidr = "10.0.0.0/16"
  vpc_tags = {
    Name = local.vpc_name
  }
}
```

## Subnet

Once the VPC is created, the next step is to define the subnets. You can refer to the `aws_subnet` implementation in the module and compare it with the manual setup from the previous post—again, the module handles much of the complexity for us.

In this case, we only need a single public subnet. The module uses `local.len_public_subnets` to determine the number of subnets and configures them via the `public_subnets` variable, so all we need to do is define that variable accordingly.

Previously, we used `aws_vpc.main.cidr_block` to calculate the subnet ranges. Now, we’ll use the output from the module—`module.vpc.vpc_cidr_block`—as defined in the module’s outputs.tf.

Additionally, `availability_zone` and `cidr_block` are supported by the module, so we just need to provide the correct input values. Note that our naming conventions may differ from the module's defaults (e.g., `subnet_names`), so we’ll need to implement custom naming logic where appropriate. The setup for private subnets is almost identical to public subnets, so we won’t repeat those details here.

Lastly, since main.tf is still relatively short, we can move the local variables from locals.tf into this file to improve readability and ease of editing.

```hcl
# main.tf
data "aws_availability_zones" "available" {}

locals {
  vpc_name = "${var.name}-vpc"
  azs      = slice(data.aws_availability_zones.available.names, 0, 1)

  public_subnets  = [for k, v in local.azs : cidrsubnet(module.vpc.vpc_cidr_block, 4, k)]
  private_subnets = [for k, v in local.azs : cidrsubnet(module.vpc.vpc_cidr_block, 4, k + 8)]
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0.0"

  # VPC
  name = var.name
  cidr = "10.0.0.0/16"
  vpc_tags = {
    Name = local.vpc_name
  }

  # Public Subnet
  azs                     = local.azs
  public_subnets          = local.public_subnets
  map_public_ip_on_launch = true
  public_subnet_names     = [for k, v in local.azs : "${var.name}-subnet-public${k + 1}-${v}"]
  public_subnet_tags = {
    Type = "Public"
  }

  # Private Subnet
  private_subnets      = local.private_subnets
  private_subnet_names = [for k, v in local.azs : "${var.name}-subnet-private${k + 1}-${v}"]
  private_subnet_tags = {
    Type = "Private"
  }
}
```

## Internet Gateway

Compared to the manually defined `aws_internet_gateway` in the previous setup, this part becomes much simpler with the module.

The `vpc_id` is automatically handled by the module, and by default, it will create an Internet Gateway for us. So all we need to do is define the tags. The only thing to watch out for is that the default naming convention might differ from what we’re used to—so I override the `igw_tags` to match the original naming logic.

Below is what the complete `module "vpc"` block looks like so far, including the VPC, subnets, and Internet Gateway configuration:

```hcl
# main.tf
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0.0"

  # VPC
  name = var.name
  cidr = "10.0.0.0/16"
  vpc_tags = {
    Name = local.vpc_name
  }

  # Public Subnet
  azs                     = local.azs
  public_subnets          = local.public_subnets
  map_public_ip_on_launch = true
  public_subnet_names     = [for k, v in local.azs : "${var.name}-subnet-public${k + 1}-${v}"]
  public_subnet_tags = {
    Type = "Public"
  }

  # Private Subnet
  private_subnets      = local.private_subnets
  private_subnet_names = [for k, v in local.azs : "${var.name}-subnet-private${k + 1}-${v}"]
  private_subnet_tags = {
    Type = "Private"
  }

  # Internet Gateway
  igw_tags = {
    Name = "${var.name}-igw"
  }
}
```

## Route Table

Next, let’s configure the Route Tables.
With the module, tasks such as creating Public and Private Route Tables, associating them with subnets, and defining the routes are all handled for us.
All we need to do is override the naming to match our own conventions.

```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0.0"

  # VPC
  name = var.name
  cidr = "10.0.0.0/16"
  vpc_tags = {
    Name = local.vpc_name
  }

  # Public Subnet
  azs                     = local.azs
  public_subnets          = local.public_subnets
  map_public_ip_on_launch = true
  public_subnet_names     = [for k, v in local.azs : "${var.name}-subnet-public${k + 1}-${v}"]
  public_subnet_tags = {
    Type = "Public"
  }

  # Private Subnet
  private_subnets      = local.private_subnets
  private_subnet_names = [for k, v in local.azs : "${var.name}-subnet-private${k + 1}-${v}"]
  private_subnet_tags = {
    Type = "Private"
  }

  # Internet Gateway
  igw_tags = {
    Name = "${var.name}-igw"
  }

  # Route Tables
  public_route_table_tags = {
    Name = "${var.name}-rtb-public"
  }
  single_nat_gateway = true
  private_route_table_tags = {
    Name = "${var.name}-rtb-private"
  }
}
```

## NACL

Finally, let’s handle the `aws_network_acl` and `aws_network_acl_rule` resources.
Since we want to create dedicated NACLs for both the Public and Private subnets, we need to enable the `public_dedicated_network_acl` and `private_dedicated_network_acl` options.

As for the specific inbound and outbound rules, the module already provides sensible defaults.
Since this setup is intended for development and testing, we don’t need to make any additional changes.
Once again, the only customization needed here is to override the NACL names to match our naming convention:

```hcl
# main.tf
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0.0"

  # VPC
  name = var.name
  cidr = "10.0.0.0/16"
  vpc_tags = {
    Name = local.vpc_name
  }

  # Public Subnet
  azs                     = local.azs
  public_subnets          = local.public_subnets
  map_public_ip_on_launch = true
  public_subnet_names     = [for k, v in local.azs : "${var.name}-subnet-public${k + 1}-${v}"]
  public_subnet_tags = {
    Type = "Public"
  }

  # Private Subnet
  private_subnets      = local.private_subnets
  private_subnet_names = [for k, v in local.azs : "${var.name}-subnet-private${k + 1}-${v}"]
  private_subnet_tags = {
    Type = "Private"
  }

  # Internet Gateway
  igw_tags = {
    Name = "${var.name}-igw"
  }

  # Route Tables
  public_route_table_tags = {
    Name = "${var.name}-rtb-public"
  }
  single_nat_gateway = true
  private_route_table_tags = {
    Name = "${var.name}-rtb-private"
  }

  # NACL
  public_dedicated_network_acl = true
  public_acl_tags = {
    Name = "${var.name}-nacl-public"
  }
  private_dedicated_network_acl = true
  private_acl_tags = {
    Name = "${var.name}-nacl-private"
  }
}
```

## Summary

This concludes the full walkthrough of refactoring the VPC setup using the [terraform-aws-modules/vpc](https://github.com/terraform-aws-modules/terraform-aws-vpc) community module.

We removed the original locals.tf and consolidated variables into main.tf to improve readability. I also prefer renaming terraform.tf to versions.tf to make version management more intuitive—though this is entirely up to your team’s conventions.

Here’s the final project structure:

```
terraform-demo/
├── backend.tf      # Backend configuration
├── main.tf         # Main infrastructure definitions (including locals)
├── outputs.tf      # Output variables
├── providers.tf    # Provider configurations
├── versions.tf     # Terraform and provider version constraints
└── variables.tf    # Input variable declarations
```

# Deployment

Next, initialize the project and generate the execution plan with the following command:

```powershell
terraform init; if ($?) { terraform plan -out=tfplan }
```

If everything looks good, apply the changes and deploy the resources with:

```powershell
terraform apply tfplan
```
