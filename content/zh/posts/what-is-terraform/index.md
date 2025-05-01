---
title: Terraform 入門與核心概念
date: 2025-05-01T14:53:19+08:00
draft: false
description:
isStarred: false
---

# Terraform 是甚麼？

[Terraform](https://github.com/hashicorp/terraform) 是由 HashiCorp 開發的一個開源 Infrastructure as Code (IaC) 工具，可以用來建置和管理雲端和地端 (On-Premises) 的資源。

它是透過組態檔 (Configuration Files) 來定義基礎架構，有以下這些功能：

- 狀態管理：Terraform State 會追蹤資源的變動
- 模組化 (Modules)：可以將重複的配置封裝成模組
- Remote Backend：支援 S3 和 Terraform Cloud 等，可以讓團隊共享狀態檔和上鎖，避免多人作業時發生衝突

# Infrastructure as Code (IaC)

基礎架構即程式碼的核心概念是：不管今天需要定義、部署或刪除基礎架構，都是透過程式碼來完成，而不是手動操作，這樣有幾個好處，像是可以透過版本控制管理檔案，也就代表可以回滾、查詢變動等，再來是一致性，確保每次部署都使用相同的設定，可以避免人為失誤，除此之外，也可以重複使用程式碼。

IaC 工具可以大致分為以下五類：

1. 腳本工具：如 Bash 和 Python
2. 組態管理工具：如 Ansible、Puppet 和 Chef
3. 伺服器模板 (Server Template) 工具：如 Docker 和 Packer
4. 調度 (Orchestration) 工具：如 Kubernetes 和 Docker Swarm
5. 配置 (Provisioning) 工具：如 Terraform、Pulumi 和 CloudFormation

# Terraform 組態語言

Terraform 採用特定領域專用語言 (domain-specific language, DSL) 來管理基礎架構，使用的語法為 [HCL](https://github.com/hashicorp/hcl/blob/main/hclsyntax/spec.md) (HashiCorp Configuration Language)。

HCL 是一種宣告式語言，開發者只需要描述最終想要的狀態，Terraform 就會自行計算和執行這些變動。

以下是使用 [Terraform Module](https://github.com/terraform-aws-modules/terraform-aws-vpc) 創建一個基礎的 VPC 範例：

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

# Terraform 如何運作

Terraform 透過遠端程序呼叫 (Remote Procedure Call, RPC) 與各種 Provider 進行 API 互動，以建置基礎架構資源。

Terraform Provider 是 Terraform Plugin 的一種，像 aws、azurerm、google 和 digitalocean 等 Provider，會對應 AWS、Azure、Google Cloud 和 DigitalOcean。除此之外，也可以對私有雲和虛擬化平台進行配置，也就是說可以在多種平台 (Provider) 上建置基礎架構。

# Terraform Workflow

Terraform 的運作流程可以分成三個步驟：

1. Write：使用 HCL 定義基礎架構組態（.tf 檔案）
2. Plan：模擬 Terraform 變更
3. Apply：執行變更，建立或修改或刪除基礎架構資源

## Terraform 主要指令解析

先介紹主要的指令，對其餘指令有興趣的話，可以透過 `terraform -help` 查詢。

| 指令 | 用途 | 內部運作 |
|-|-|-|
| terraform init | 初始化專案 | 下載 Provider、初始化 backend 和 驗證 Terraform 版本等 |
| terraform validate | 檢驗組態檔是否正確 | 檢查 Terraform 檔案，像是符號正不正確，或是少了變數，或有重複的 provider 等 |
| terraform plan | 預覽變更，顯示 Terraform 即將執行的修改 | 載入 Terraform State、解析組態與變數，以及計算需要變更的資源等 |
| terraform apply | 套用變更，建立或更新資源 | 載入 plan 檔案、與 Backend 同步狀態和執行變更並更新 Terraform State 等 |
| terraform destroy | 刪除資源 | 刪除由 Terraform 管理的資源 |

如果想要看更多關於該指令的說明，可以使用 `terraform <指令> -help` 查詢。
