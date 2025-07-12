---
title: 使用 Terraform 建立 AWS VPC
date: 2025-07-12T22:56:30+08:00
draft: false
description:
isStarred: false
---

- 作業系統：Windows 11
- Terraform 版本：1.10.5

看完前一篇已經初步認識 Terraform的基本概念，這篇會透過實際動手做一次來加深印象。
為避免越級打怪，本篇會帶領讀者一步步簡單的使用 resource 來建立 AWS VPC，下一篇再以 Module 重構。
VPC 是 AWS 提供的虛擬網路服務，能夠在雲端中建立一個隔離的網路環境，有興趣深入的讀者可以參考[官方文件](https://docs.aws.amazon.com/vpc/latest/userguide/what-is-amazon-vpc.html)。

本篇主要的目標是透過 Terraform 建立以下資源：

- 1 個 VPC
- 1 個 Public Subnet
- 1 個 Private Subnet
- 2 個 Route Table
- 2 個 Network ACL
- 1 個 Internet Gateway

# 前置準備

在正式開始撰寫 Terraform 組態前，我們需要先把本機環境準備好，這裡以 Windows 系統為主進行說明。

## 安裝 Terraform

非 Windows 的開發者可參考 [Install Terraform](https://developer.hashicorp.com/terraform/install)。

首先，開啟 PowerShell，輸入以下指令建立 Terraform 的安裝資料夾：

```powershell
mkdir "$env:LOCALAPPDATA\Programs\Terraform\bin"
```

根據你的 CPU 架構下載適用版本，這裡我們下載 [Windows 的 AMD64 v1.10.5 的 Terraform zip 檔](https://releases.hashicorp.com/terraform/1.10.5/terraform_1.10.5_windows_amd64.zip)，然後解壓縮到剛剛建立的資料夾。

解壓完成後，前往「使用者環境變數」，在 `Path` 中新增以下路徑：

```
%LOCALAPPDATA%\Programs\Terraform\bin
```

完成後重啟 PowerShell，輸入以下指令確認是否安裝成功：

```powershell
terraform -version
```

若出現 Terraform v1.10.5 on windows_amd64 則代表安裝成功。

## AWS 設置

### 安裝 AWS CLI

根據作業系統，依照[官方文件](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)進行安裝。

### 設定 AWS Profile

AWS CLI 的設定資訊會儲存在 `$env:UserProfile\.aws` 下，這裡我們先建立一個預設的 profile，輸入以下指令：

```powershell
aws configure
```

依序填入：

1. Access Key
2. Secret Access Key
3. 預設區域（如 ap-northeast-1）
4. 輸出格式（如 json）

# 撰寫 HCL

根據[官方建議](https://www.notion.so/Terraform-AWS-VPC-21302d46621680089625ffb854fef1b2?pvs=21)，我們先建立以下幾個檔案：main.tf、variables.tf、outputs.tf、terraform.tf、providers.tf、backend.tf 和 locals.tf。建立完成後的專案結構如下：

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

## 定義 Terraform 與 Provider 版本

在開始撰寫 VPC 等資源之前，我們需要先定義 Terraform 所需的版本與使用的 Provider。這裡採用 Terraform 1.0 以上版本，並使用 AWS Provider 6.3.X：

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

## 使用本地 Backend

預設情況下，Terraform 就會使用本地 Backend，也就是把狀態檔儲存在專案資料夾中，不過這裡我們還是手動寫出來，這樣比較清楚未來要換成遠端 Backend 時該修改哪裡：

```hcl
# backend.tf
terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}
```

>💡 如果你省略 backend 區塊，Terraform 還是會預設使用本地狀態檔，所以這個設定不是必須，但會讓架構更清楚。

## VPC

我們先從最基本的 VPC 開始。首先，在變數檔中定義 VPC 的名稱前綴以及一個 CIDR 範圍：

```hcl
# variables.tf
variable "name" {
  description = "Name of the VPC"
  type        = string
  default     = "demo"
}
```

接著，在 locals.tf 中組合出完整的 VPC 名稱，並選擇一個可用區（Availability Zone）來簡化架構。我們這裡只使用一個 AZ：

```hcl
# locals.tf
data "aws_availability_zones" "available" {}

locals {
  vpc_name = "${var.name}-vpc"
  azs      = slice(data.aws_availability_zones.available.names, 0, 1)
}
```

最後，在 main.tf 中定義一個 VPC，並開啟 DNS 支援：

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

接下來，我們要為 VPC 建立一個 Public Subnet 和一個 Private Subnet。為了讓每個 Subnet 的 CIDR 不重疊，我們會使用 Terraform 的 cidrsubnet 函式來自動計算每個 Subnet 的網段。

在 locals.tf 中加入以下內容，分別計算 Public 和 Private Subnet 的 CIDR：

```hcl
# locals.tf
locals {
  public_subnets  = [for k, v in local.azs : cidrsubnet(aws_vpc.main.cidr_block, 4, k)]
  private_subnets = [for k, v in local.azs : cidrsubnet(aws_vpc.main.cidr_block, 4, k + 8)]
}
```

>💡 cidrsubnet(base, newbits, netnum) 是用來從現有的 CIDR 中切割出子網。
>   這裡我們把 /16 切成多個 /20 子網（因為 4 = 20 - 16），並用不同的 netnum 避免重複。

接著，在 main.tf 中建立 Public 和 Private Subnet：

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

因為我們建立了 Public Subnet，接下來就需要讓這些子網能夠連上 Internet，因此要為 VPC 加上一個 Internet Gateway。

```hcl
# main.tf
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.name}-igw"
  }
}
```

>💡 Internet Gateway 是連接 VPC 到公網（Internet）的出入口，只有有被正確路由指向且開啟 map_public_ip_on_launch 的 Subnet，才算真正的「Public」。

## Route Table

接下來，我們要設定 Route Table，讓 Subnet 能夠對外通訊。Public Subnet 需要透過 Internet Gateway 來連接 Internet，而 Private Subnet 則維持內部網路通訊。

首先為 Public Subnet 建立一張 Route Table，並設定路由讓它能透過 IGW 對外通訊：

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

Private Subnet 不需要連接 IGW，但需要跟其他子網溝通：

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

接下來我們為 Public 和 Private Subnet 建立對應的 NACL（Network ACL）。NACL 是一種子網層級的網路存取控制機制，可以設定允許或拒絕的流量規則。目前我們先全部開放，方便測試與開發，之後可以再視情況進行收斂。

Public Subnet 的 NACL

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

Private Subnet 的 NACL

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

## 部署

上述的檔案與設定都完成後，就可以開始部署了。

### 整理格式

先使用以下指令整理 .tf 檔案的排版，讓格式更一致、易於閱讀：

```powershell
terraform fmt
```

### 初始化專案

初始化 Terraform 專案，下載 provider 並建立執行環境：

```powershell
terraform init
```

執行後會看到新增了 `.terraform/` 資料夾和 `.terraform.lock.hcl` 檔案：

- `.terraform/`：裡面包含 provider 的執行檔、Terraform 所使用的版本資訊，以及 backend 的初始化狀態。
- `.terraform.lock.hcl`：記錄目前使用的 provider 版本，確保多人協作或日後執行時版本一致，避免因升級而導致非預期的變更。

### 套用變更

接下來就可以將定義好的資源部署到 AWS：

```powershell
terraform apply
```

照畫面提示輸入 `yes` 即可開始執行。完成後，就會看到 VPC、子網、NACL 等資源已經建立在 AWS 上。這時候專案根目錄下也會出現一個 `terraform.tfstate` 檔案，裡面記錄了 Terraform 管理的所有資源狀態。

### 銷毀資源

如果是測試用資源或想清空環境，可以使用以下指令銷毀所有由 Terraform 管理的資源：

```powershell
terraform destroy
```

跟 apply 一樣，輸入 `yes` 確認即可開始銷毀流程。

銷毀完成後，再去查看根目錄下的 `terraform.tfstate` 檔案，會發現 `resources` 變成空陣列，除此之外，還多了一個 `terraform.tfstate.backup` 檔案，裡面記錄了上一次成功套用的狀態。
