---
title: 使用 Terraform Module 重構 AWS VPC
date: 2025-07-20T18:21:53+08:00
draft: false
description:
isStarred: false
---

- 作業系統：Windows 11
- PowerShell 版本：5.1
- Terraform 版本：1.10.5

模組化能讓我們將基礎架構封裝成可重複使用的單元，提升可維護性和一致性。

這篇文章會延續上一篇《使用 Terraform 建立 AWS VPC》。當時我們是手動撰寫多個 resource 來創建 VPC 和其相關資源，這次將改用由社群維護的 [Terraform AWS modules](https://registry.terraform.io/namespaces/terraform-aws-modules) 來進行重構。

為什麼選用這個模組？
每個開發者撰寫 HCL 的風格都不同，除非公司有統一維護一套模組，否則分發給外包或由各部門各自實作，最後往往會難以整合或除錯。而這個模組不僅穩定成熟，也具備高度彈性與完整的文件，是筆者在開發時偏好的選擇。

# Git Clone VPC Module

筆者習慣先把模組的原始碼 clone 下來，方便查看範例與各項參數的使用方式。

```powershell
git clone https://github.com/terraform-aws-modules/terraform-aws-vpc.git
```

這個 repo 裡面包含許多檔案，我們可以先專注在以下幾個重點檔案，從中參考如何撰寫，而閱讀範例本身就是很好的學習方式。

```
terraform-aws-vpc/
├── examples/       # 使用範例
├── modules/        # VPC 的子模組
├── main.tf         # 模組內的資源定義
├── outputs.tf      # 輸出變數定義
├── variables.tf    # 可設定的輸入變數
└── versions.tf     # Terraform 和 Provider 的版本設定
```

# 重構

這是上一篇的檔案結構，我們會從 main.tf 開始逐步改寫成模組化版本：

```
terraform-demo/
├── backend.tf      # Backend 設定
├── locals.tf       # Local 變數定義
├── main.tf         # 主要資源定義
├── outputs.tf      # 輸出結果定義
├── providers.tf    # 所有 provider 的設定
├── terraform.tf    # Terraform 核心設定（版本與使用的 provider）
└── variables.tf    # Input 變數宣告
```

## VPC

我們可以對照官方模組中 `aws_vpc` 的實作與上一篇手動撰寫的版本，會發現模組已經幫我們包好各種資源，我們只需要傳入對應的變數即可。

例如：

- `cidr_block` 支援 IPAM 的邏輯判斷，但我們目前不需要，所以直接指定 CIDR 即可。
- `enable_dns_hostnames` 和 `enable_dns_support` 在模組中預設為 true，因此不需另外設定（可以參考模組內的 variables.tf）。
- name 是個常用變數，在模組內會套用到各資源的 tag。為了讓命名更符合需求（不想加上 -vpc 結尾），我們可以透過 vpc_tags 明確覆寫 Name tag，這裡會用到 [merge function](https://developer.hashicorp.com/terraform/language/functions/merge)。

以下是改寫後的 aws_vpc，在本文撰寫時，模組版本為 v6.0.1：

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

有了 VPC 之後，接下來就需要劃分子網。這部分可以參考模組內的 `aws_subnet` 實作，對照上一篇的手動寫法，會發現模組也幫我們處理好了。

我們只需要建立一個 public subnet。模組中用 `local.len_public_subnets` 判斷數量，並透過變數 `public_subnets` 進行配置，因此我們只需要定義這個變數即可。

上一篇中我們使用了 `aws_vpc.main.cidr_block` 來計算 subnet 的範圍，但現在改用模組的 output，也就是 `module.vpc.vpc_cidr_block`，這點可以參考模組的 outputs.tf。

另外 `availability_zone` 和 `cidr_block` 的設定模組也都有支援，我們只要提供合適的值。值得注意的是，由於我們命名方式與模組預設略有不同，像是 `subnet_names`，就需要自己處理命名邏輯。Private Subnet 的做法與 Public Subnet 幾乎一致，這裡就不再重複說明。

最後，由於 main.tf 行數不多，我們也可以把原本放在 locals.tf 的變數搬回來，方便整體閱讀與編輯。

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

相比之前手動撰寫的 `aws_internet_gateway`，模組化後這部分就更簡單了。

`vpc_id` 已經由模組自動幫我們處理好，預設也會建立 Internet Gateway，所以只需要設定 tag 就可以了。這裡唯一要注意的，就是命名方式可能與我們原本習慣的不太一樣，因此我額外覆寫了 `igw_tags` 來對應原本的命名邏輯。

以下是目前為止整體 `module "vpc"` 的樣子，已包含 VPC、Subnets 和 Internet Gateway 的設定：

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

接著我們來設定 Route Table。使用模組之後，像是 Public 與 Private Route Table 的建立、子網的關聯，以及路由的設定等，模組都已經幫我們處理好了，我們只需要覆寫名稱的部分即可。

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

最後來處理 `aws_network_acl` 和 `aws_network_acl_rule` 的部分。由於我們希望為 Public 與 Private Subnet 各自建立獨立的 NACL，因此需要啟用 `public_dedicated_network_acl` 和 `private_dedicated_network_acl`。

至於具體的 Inbound/Outbound 規則，模組已經幫我們預設好了，因為只是開發測試用，一樣不需要額外修改。這裡我們同樣只需要自訂 NACL 的名稱即可：

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

## 總結

以上就是使用 [terraform-aws-modules/vpc](https://github.com/terraform-aws-modules/terraform-aws-vpc) 模組重構 VPC 架構的完整流程。

我們移除了原本的 `locals.tf`，將變數直接集中在 `main.tf` 以提升可讀性。筆者另外習慣將 `terraform.tf` 改為 `versions.tf`，便於管理版本設定。不過這部分也可以依照團隊規範進行調整。

最終的專案結構如下：

```
terraform-demo/
├── backend.tf      # Backend 設定
├── main.tf         # 主要資源定義（含 locals）
├── outputs.tf      # 輸出結果定義
├── providers.tf    # 所有 provider 的設定
├── versions.tf     # Terraform 核心設定（版本與使用的 provider）
└── variables.tf    # Input 變數宣告
```

# 部署

接著使用以下指令來初始化專案並產生變更計畫：

```powershell
terraform init; if ($?) { terraform plan -out=tfplan }
```

若變更無誤，接下來輸入以下指令即可套用變更、部署資源：

```powershell
terraform apply tfplan
```
