---
title: 'Getting Started with Terraform: Core Concepts and Fundamentals'
date: 2025-05-01T14:53:19+08:00
draft: false
description:
isStarred: false
---

# What is Terraform?

[Terraform](https://github.com/hashicorp/terraform) is an open-source Infrastructure as Code (IaC) tool developed by HashiCorp. It supports the provisioning of both cloud and on-premises resources.

Infrastructure is defined through configuration files, offering several key features:

- State Management: Terraform uses a state file to track resource changes and updates.
- Modules: Reusable components that encapsulate repeated configurations, improving maintainability.
- Remote Backend: Supports backends like S3 and Terraform Cloud, allowing teams to share state files and enabling state locking to prevent conflicts during concurrent updates.

# Infrastructure as Code (IaC)

The core concept of Infrastructure as Code (IaC) is that you can deploy, update, or destroy infrastructure using code, rather than performing manual operations.
 This approach offers several benefits:

- Version Control: Since infrastructure is defined in code, it can be managed using version control tools like Git. This allows you to track changes, revert to previous versions, and maintain a clear history.
- Consistency: Using the same code ensures the same infrastructure setup every time, reducing human error and improving reliability.
- Reusability: IaC encourages reusability, allowing you to define infrastructure once and use it across multiple environments.

IaC tools can be categorized into five groups:

1. Shell Scripting Tools – e.g., Bash, Python
1. Configuration Management Tools – e.g., Ansible, Puppet, Chef
1. Server Template Tools – e.g., Docker, Packer
1. Orchestration Tools – e.g., Kubernetes, Docker Swarm
1. Provisioning Tools – e.g., Terraform, Pulumi, CloudFormation

# Terraform Language

Terraform uses a domain-specific language (DSL) to manage infrastructure, known as [HCL](https://github.com/hashicorp/hcl/blob/main/hclsyntax/spec.md) — the HashiCorp Configuration Language.

HCL is a declarative language, meaning developers only need to describe the desired end state of the infrastructure. Terraform will automatically calculate the necessary steps to reach that state and execute the required changes.

Below is an example of how to create a simple VPC using the [Terraform Module](https://github.com/terraform-aws-modules/terraform-aws-vpc).

```hcl
data "aws_availability_zones" "available" {}

locals {
  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.19.0"

  name = "demo-vpc"
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
}
```

# How Terraform Works

Terraform provisions infrastructure by interacting with provider APIs through Remote Procedure Calls (RPC).

A Terraform Provider is a type of plugin that allows Terraform to communicate with specific platforms. Common providers include aws, azurerm, google, and digitalocean, which correspond to AWS, Azure, Google Cloud, and DigitalOcean respectively.

In addition to public cloud platforms, Terraform can also provision resources in private clouds and virtualized environments. This means Terraform can manage infrastructure across a wide variety of platforms—both cloud-based and on-premises—through its extensible provider system.

# Terraform Workflow

The Terraform workflow consists of three main steps:

1. Write – Define infrastructure using configuration files (.tf files) written in HCL (HashiCorp Configuration Language).
1. Plan – Preview the changes Terraform will make without applying them. This helps validate and review the planned modifications.
1. Apply – Execute the proposed changes to create, update, or destroy infrastructure resources as defined in the configuration.

## Terraform Main Commands

This section introduces only the main Terraform commands. For a complete list, you can run `terraform -help`.

| Command | Purpose | How It Works |
|-|-|-|
| terraform init | Initialize the project | Downloads the necessary providers, initializes the backend, and verifies the Terraform version. |
| terraform validate | Validate configuration files | Checks for syntax errors, missing variables, duplicate providers, and other issues in the configuration files. |
| terraform plan | Preview changes | Loads the Terraform state, parses configuration and variables, and calculates the resource changes needed. |
| terraform apply | Apply changes | 	Applies the planned changes by syncing with the backend, executing updates, and saving the new Terraform state. |
| terraform destroy | Destroy managed resources | Removes all infrastructure resources managed by Terraform. |

To learn more about any specific command, use `terraform <command> -help`.
