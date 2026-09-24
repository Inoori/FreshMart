# FreshMart · 同城生鲜履约系统

> 基于 .NET 10 + Minimal API + 模块化单体 + 整洁架构 + 垂直切片 + DDD + 事件驱动的同城生鲜电商履约系统。

📋 **开发计划看板**：[GitHub Projects #2](https://github.com/users/Inoori/projects/2)

用户在同城门店下单生鲜商品，系统完成商品搜索、库存预占、支付、订单确认、骑手配送、通知与审计。

---

## 目录

- [项目定位](#项目定位)
- [核心业务规则](#核心业务规则)
- [技术栈](#技术栈)
- [架构概览](#架构概览)
- [限界上下文](#限界上下文)
- [核心流程](#核心流程)
- [解决方案结构](#解决方案结构)
- [可观测性](#可观测性)
- [开发路线](#开发路线)
- [快速开始](#快速开始)
- [关键设计](#关键设计)
- [测试](#测试)
- [部署](#部署)
- [拆分微服务路线](#拆分微服务路线)

---

## 项目定位

**一句话：** 用户在同城门店下单生鲜商品，系统完成商品搜索、库存预占、支付、订单确认、骑手配送、通知与审计。

### 角色

| 角色 | 职责 |
|---|---|
| 消费者 | 搜索商品、加购、下单、支付、查订单、评价 |
| 商家 | 上架商品、改价、上下架、查看门店订单 |
| 骑手 | 接配送任务、取货、送达 |
| 运营 | 查看订单、库存、审计日志 |
| 系统 | 库存预占、支付回调、超时取消、消息重试、搜索索引 |

---

## 核心业务规则

- 商品属于某个门店，库存按 `StoreId + SkuId` 管理。
- 用户下单时预占库存，预占有效期 **15 分钟**。
- 支付成功：扣减库存，订单进入 `Paid`，生成配送任务。
- 支付超时/失败：取消订单，释放库存。
- 支付回调必须幂等，同一 `PaymentId` 不能重复扣款。
- 库存不能超卖，使用 **PostgreSQL 乐观并发 + Redis 分布式锁**。
- 商品变更后，Elasticsearch 搜索索引最终一致。
- 配送任务只能被一个骑手接单。
- 所有关键操作写审计日志到 Elasticsearch。
- 订单、库存、支付、配送之间通过领域事件 + 集成事件最终一致。

### 订单状态机

~~~text
PendingPayment ──► Paid ──► Preparing ──► Delivering ──► Completed
      │              │
      ▼              ▼
  Cancelled      Refunding ──► Cancelled
~~~

---

## 技术栈

| 层次 | 技术 |
|---|---|
| 语言/框架 | .NET 10、ASP.NET Core Minimal API |
| 架构模式 | 模块化单体、整洁架构、垂直切片、DDD、CQRS、事件驱动 |
| 进程内分发 | WolverineFx（内建 Mediator 模式） |
| 集成事件 | Wolverine + RabbitMQ（Outbox、Saga、重试、死信） |
| AOP | Metalama（日志、事务、缓存、幂等、审计、重试、验证） |
| 可观测性 | OpenTelemetry SDK + OTLP；开发 Aspire Dashboard，生产 EDOT Collector + Elasticsearch + Kibana |
| 数据库 | PostgreSQL 16（多 Schema） |
| 缓存/锁 | Redis 7 |
| 消息 | RabbitMQ 3.13 |
| 搜索 | Elasticsearch 8.x |
| 部署 | Podman / Docker、Kubernetes、Nginx |
| 测试 | xUnit v3、FluentAssertions、Testcontainers、NetArchTest |

---

## 架构概览

~~~mermaid
graph TB
    Nginx["Nginx Ingress"]
    Api["FreshMart.Api"]
    Worker["FreshMart.Worker"]
    PG[("PostgreSQL<br/>多 Schema + Outbox")]
    Rds[("Redis<br/>缓存 / 锁 / 幂等键")]
    MQ["RabbitMQ<br/>集成事件 + Saga"]
    ES[("Elasticsearch<br/>搜索 + 审计")]
    EDOT["EDOT Collector"]

    Nginx --> Api
    Nginx --> Worker
    Api --> PG
    Api --> Rds
    Api --> MQ
    Worker --> PG
    Worker --> MQ
    MQ --> ES
    Api -. OTLP .-> EDOT
    Worker -. OTLP .-> EDOT
    EDOT -. OTLP .-> ES
~~~

**依赖方向：**

~~~mermaid

graph LR
    H["Hosts<br/>Api / Worker"]
    M["Modules<br/>Domain → Application → Infrastructure → Api"]
    BB["BuildingBlocks<br/>Shared.Core / Persistence / Web / ..."]

    H --> M
    M --> BB
~~~

- **BuildingBlocks**：跨模块共享的基元、抽象、契约，零业务语义。
- **Modules**：每个限界上下文一个文件夹，内含 4 个 csproj，模块间编译期隔离。
- **Hosts**：宿主只做聚合注册，调用每个模块的 `AddXxxInfrastructure` 和 `MapXxxEndpoints`。

---

## 限界上下文

| 上下文 | 聚合根 | 主要值对象 | 领域事件 |
|---|---|---|---|
| Catalog 商品目录 | `Product` | `Money`、`Category`、`Sku` | `ProductCreated`、`ProductPriceChanged`、`ProductOnShelf` |
| Inventory 库存 | `InventoryItem` | `Quantity`、`StoreSku` | `InventoryReserved`、`InventoryReleased`、`InventoryDeducted` |
| Cart 购物车 | `Cart` | `CartItem`、`Quantity` | `CartItemAdded`、`CartCheckedOut` |
| Ordering 订单 | `Order` | `Address`、`OrderItem`、`Money` | `OrderPlaced`、`OrderPaid`、`OrderConfirmed`、`OrderCancelled`、`OrderCompleted` |
| Payment 支付 | `Payment` | `Money`、`PaymentNo` | `PaymentInitiated`、`PaymentSucceeded`、`PaymentFailed`、`PaymentTimedOut` |
| Delivery 配送 | `DeliveryTask` | `RiderId`、`TimeRange` | `DeliveryTaskCreated`、`DeliveryAssigned`、`DeliveryPickedUp`、`DeliveryCompleted` |
| Notification 通知 | `Notification` | `Channel`、`Template` | `NotificationSent` |
| Search 搜索 | `ProductIndex` | `SearchDoc` | `ProductIndexed` |
| Audit 审计 | `AuditLog` | `Actor`、`Action` | `AuditRecorded` |
| Identity 身份 | `User` | `UserRole` | `UserRegistered`、`RoleGranted` |

---

## 核心流程

### 流程 A：商品上架与搜索

~~~text
商家 POST /api/catalog/products
  └─► Catalog.Api CreateProduct 端点
       └─► WolverineFx 分发 CreateProductCommand
            └─► 创建 Product 聚合，发布 ProductCreated
                 └─► Wolverine Outbox 发 ProductChangedIntegrationEvent 到 RabbitMQ
                      └─► Search Worker 消费，写 Elasticsearch

用户 GET /api/catalog/products/search?q=牛奶
  └─► 查询走 Elasticsearch
用户 GET /api/catalog/products/{id}
  └─► 先读 Redis，未命中再读 PostgreSQL
~~~

### 流程 B：下单、库存预占、支付、确认

~~~text
POST /api/orders
  └─► Ordering.Application PlaceOrderCommand 校验购物车、地址、商品状态
       └─► 通过 IInventoryClient 抽象接口预占库存（单体为进程内实现）
       └─► 创建 Order（PendingPayment），发布 OrderPlaced
            └─► OrderFulfillmentSaga 启动，等待 InventoryReserved + PaymentSucceeded

POST /api/payments/callback
  └─► Payment.Application 幂等处理，发布 PaymentSucceeded
       └─► Saga 收到两个事件 → ConfirmOrderCommand → 扣减库存 → OrderConfirmed
            └─► Delivery.Application 创建 DeliveryTask，通知骑手
                 └─► 骑手接单、取货、送达 → DeliveryCompleted
                      └─► 订单 Completed，通知用户，审计写 ES
~~~

### 流程 C：支付超时取消

~~~text
下单时 Wolverine 延时消息 15 分钟后检查
  └─► 若仍未支付 → CancelOrderCommand
       └─► OrderCancelled → 库存释放 → 通知用户 → 审计记录
~~~

### 流程 D：库存不足或支付失败

~~~text
库存预占失败 → InventoryReservationFailed
  └─► Saga 取消订单，若已支付则发起模拟退款
       └─► 通知用户，释放相关资源
~~~

---

## 解决方案结构

~~~text
FreshMart/
├── src/
│   ├── BuildingBlocks/
│   │   ├── FreshMart.Shared.Core/               # 零依赖：领域基元、抽象、Result、Guard
│   │   ├── FreshMart.Shared.Persistence/        # EF Core 通用配置
│   │   ├── FreshMart.Shared.Web/                # Web 扩展、Security
│   │   ├── FreshMart.Shared.Validation/         # FluentValidation 扩展
│   │   ├── FreshMart.Shared.Messaging/          # Wolverine 封装、Outbox 基类
│   │   └── FreshMart.Shared.Contracts/          # 集成事件契约
│   │
│   ├── Catalog/                                 # 每个模块 4 个 csproj
│   │   ├── FreshMart.Catalog.Domain/            # 只引用 Shared.Core
│   │   ├── FreshMart.Catalog.Application/       # Domain + Shared.Core + Shared.Validation
│   │   ├── FreshMart.Catalog.Infrastructure/    # Application + Domain + Shared.Persistence/Messaging/Contracts
│   │   └── FreshMart.Catalog.Api/               # Application + Domain + Shared.Web
│   │
│   ├── Inventory/
│   ├── Cart/
│   ├── Ordering/
│   ├── Payment/
│   ├── Delivery/
│   ├── Notification/
│   ├── Search/
│   ├── Audit/
│   ├── Identity/
│   │
│   ├── FreshMart.Api/                           # API 宿主（Microsoft.NET.Sdk.Web）
│   └── FreshMart.Worker/                        # Worker 宿主（Microsoft.NET.Sdk）
│
├── tests/
│   ├── FreshMart.Catalog.Tests/
│   ├── FreshMart.Ordering.Tests/
│   ├── FreshMart.IntegrationTests/
│   └── FreshMart.ArchitectureTests/
│
├── deploy/
│   ├── docker/
│   ├── k8s/
│   └── nginx/
│
├── scripts/
│   ├── create-freshmart.sh
│   ├── setup-github-project.sh
│   └── cleanup-all.sh
│
├── Directory.Build.props
├── Directory.Packages.props
├── .editorconfig
├── .gitattributes
├── .gitignore
├── FreshMart.slnx
└── README.md
~~~

**项目总数：** 6 (BuildingBlocks) + 40 (10 模块 × 4 层) + 2 (Hosts) + 4 (Tests) = **52 个**

### 项目引用规则（严格分层）

| 项目 | 可引用 | 禁止引用 |
|---|---|---|
| `FreshMart.Shared.Core` | 无 | 所有其他项目 |
| `FreshMart.Shared.Persistence` | `Shared.Core` | 其他 `Shared.*` |
| `FreshMart.Shared.Web` | `Shared.Core` | 其他 `Shared.*` |
| `FreshMart.Shared.Validation` | `Shared.Core` | 其他 `Shared.*` |
| `FreshMart.Shared.Messaging` | `Shared.Core` | 其他 `Shared.*` |
| `FreshMart.Shared.Contracts` | `Shared.Core` | 其他 `Shared.*` |
| `FreshMart.{X}.Domain` | `Shared.Core` | EF Core / ASP.NET Core / FluentValidation |
| `FreshMart.{X}.Application` | `Domain` + `Shared.Core` + `Shared.Validation` | `Infrastructure` |
| `FreshMart.{X}.Infrastructure` | `Application` + `Domain` + `Shared.Persistence` + `Shared.Messaging` + `Shared.Contracts` | `Api` |
| `FreshMart.{X}.Api` | `Application` + `Domain` + `Shared.Web` | `Infrastructure` |
| `FreshMart.Api`（宿主） | `Shared.Core` + `Shared.Web` + 所有模块 `.Api` + 所有模块 `.Infrastructure` | `Worker` |
| `FreshMart.Worker`（宿主） | `Shared.Core` + `Shared.Messaging` + 所有模块 `.Infrastructure` | `Api` |

**关键约束：**

- **Domain 只引用 `Shared.Core`**，编译期强制不碰 EF Core、ASP.NET Core、FluentValidation。
- **模块之间不互相引用**，跨模块通信只通过 `Shared.Contracts` 中的集成事件和 `Application/Abstractions/` 中的接口。
- **`Api` 项目只引用 `Application` + `Shared.Web`**，不引用 `Infrastructure`。
- **宿主负责组合**，引用所有模块的 `Api` 和 `Infrastructure` 做 DI 注册。

### 每个模块的内部结构

以 `Catalog` 为例：

~~~text
src/Catalog/
├── FreshMart.Catalog.Domain/                   # 只引用 Shared.Core
│   ├── Product.cs
│   ├── Sku.cs
│   ├── ProductStatus.cs
│   ├── ValueObjects/
│   └── Events/
│
├── FreshMart.Catalog.Application/              # 引用 Domain + Shared.Core + Shared.Validation
│   ├── Features/                               # 垂直切片
│   │   ├── CreateProduct/
│   │   ├── ChangePrice/
│   │   └── SearchProducts/
│   ├── Abstractions/                           # 跨用例共享接口
│   └── Sagas/
│
├── FreshMart.Catalog.Infrastructure/           # 引用 Application + Domain + Shared.*
│   ├── Persistence/
│   │   ├── CatalogDbContext.cs
│   │   ├── Configurations/
│   │   └── Repositories/
│   ├── Messaging/
│   ├── Clients/
│   └── CatalogModule.cs                        # AddCatalogInfrastructure
│
└── FreshMart.Catalog.Api/                      # 引用 Application + Domain + Shared.Web
    ├── Features/                               # 垂直切片
    │   └── CreateProduct/
    │       ├── CreateProductEndpoint.cs
    │       └── CreateProductRequest.cs
    └── (含 FrameworkReference Microsoft.AspNetCore.App)
~~~

---

## 可观测性

应用通过 **OpenTelemetry SDK** 统一采集 traces / metrics / logs，通过 **OTLP 协议**导出。后端在开发和生产不同，**应用代码完全一致，只改环境变量**。

### 架构

~~~text
应用 (OTel SDK) ──► OTLP Endpoint ──► 后端
~~~

| 环境 | OTLP Endpoint | 查看 |
|---|---|---|
| **开发** | `http://localhost:4317` | Aspire Dashboard (http://localhost:18888) |
| **生产** | `http://otel-collector:4317` | EDOT Collector → Elasticsearch → Kibana |

### 开发环境

~~~bash
docker run --rm -it -d \
  -p 18888:18888 \
  -p 4317:18889 \
  -e DOTNET_DASHBOARD_UNSECURED_ALLOW_ANONYMOUS=true \
  --name aspire-dashboard \
  mcr.microsoft.com/dotnet/aspire-dashboard:9.0
~~~

访问 http://localhost:18888 查看 traces / metrics / logs。

### 应用接入代码

~~~csharp
builder.Services.AddOpenTelemetry()
    .ConfigureResource(r => r.AddService(
        serviceName: builder.Environment.ApplicationName,
        serviceVersion: "1.0.0"))
    .WithTracing(t => t
        .AddAspNetCoreInstrumentation()
        .AddHttpClientInstrumentation()
        .AddEntityFrameworkCoreInstrumentation()
        .AddSource("Wolverine")
        .AddSource("FreshMart.*"))
    .WithMetrics(m => m
        .AddAspNetCoreInstrumentation()
        .AddHttpClientInstrumentation()
        .AddRuntimeInstrumentation()
        .AddMeter("Wolverine")
        .AddMeter("FreshMart.*"))
    .WithLogging(l => l.AddOpenTelemetry())
    .UseOtlpExporter();
~~~

**注意**：不要同时使用 `UseOtlpExporter()` 和 `AddOtlpExporter()`，会抛 `NotSupportedException`。

---

## 开发路线

| 里程碑 | 目标 | 验收标准 |
|---|---|---|
| **M0** | 骨架与开发环境就绪 | `dotnet build` 通过；Aspire Dashboard 显示 trace |
| **M1** | BuildingBlocks 完成 | 领域基元可复用；单元测试通过 |
| **M2** | Catalog 打通 | 商品上架 → 事件 → ES → 搜索，端到端可演示 |
| **M3** | 订单与库存 MVP | 下单 → 预占 → 支付 → 确认，正常流程可演示 |
| **M4** | 履约闭环 | 配送任务 → 接单 → 完成；订单 Completed |
| **M5** | 异常与一致性 | 超时取消、库存不足、支付失败、幂等、并发不超卖 |
| **M6** | 辅助模块 | Cart / Notification / Audit / Identity / Search |
| **M7** | 生产就绪 | K8s 部署 + 可观测性完善 + 测试覆盖 > 70% |
| **M8** | 稳定性验证 | 500 并发不超卖；故障可恢复 |
| **M9** | 微服务拆分（可选） | 按模块拆服务，各服务独立部署 |

每个里程碑的详细 Issue 见 [GitHub Project #2](https://github.com/users/Inoori/projects/2)。

---

## 快速开始

### 前置条件

- [.NET 10 SDK](https://dotnet.microsoft.com/download/dotnet/10.0)
- [Podman](https://podman.io/) 或 [Docker](https://www.docker.com/)

### 1. 克隆仓库

~~~bash
git clone https://github.com/Inoori/FreshMart.git
cd FreshMart
~~~

### 2. 恢复依赖并构建

~~~bash
dotnet restore
dotnet build
~~~

### 3. 启动依赖中间件

~~~bash
cd deploy/docker
podman compose up -d
~~~

| 服务 | 端口 | 说明 |
|---|---|---|
| PostgreSQL | 5432 | 多 Schema 主库 |
| Redis | 6379 | 缓存 / 锁 / 幂等键 |
| RabbitMQ | 5672 / 15672 | 消息队列 / 管理台 |
| Elasticsearch | 9200 | 搜索 / 审计 |
| Kibana | 5601 | ES 可视化 |
| Aspire Dashboard | 18888 / 4317 | OTel 可视化（开发） |

### 4. 应用数据库迁移

~~~bash
dotnet ef database update \
  --project src/FreshMart.Api \
  --startup-project src/FreshMart.Api
~~~

### 5. 启动 API 与 Worker

~~~bash
# 终端 1
dotnet run --project src/FreshMart.Api

# 终端 2
dotnet run --project src/FreshMart.Worker
~~~

### 6. 访问

| 服务 | 地址 |
|---|---|
| API 文档 | http://localhost:5000/scalar |
| Aspire Dashboard | http://localhost:18888 |
| RabbitMQ 管理台 | http://localhost:15672（guest / guest） |
| Kibana | http://localhost:5601 |

---

## 关键设计

### 库存防超卖

- **Redis 分布式锁**：`lock:inventory:{storeId}:{skuId}`，避免同 SKU 并发冲突。
- **PostgreSQL 条件更新**：`UPDATE ... WHERE available >= @qty`，原子扣减。
- **乐观并发**：`Version` 列作为 `IsConcurrencyToken`，冲突时重试。
- **预占 TTL**：15 分钟，通过 Wolverine 延时消息触发释放。

### 支付幂等

- `PaymentId` 唯一约束。
- `Payment.MarkSucceeded` 对已成功状态直接返回 `false`，不重复发事件。
- Redis 幂等键 `idem:payment:{paymentId}` 做前置拦截，TTL 24h。

### 最终一致

- 写模型与 Outbox 在同一 PostgreSQL 事务。
- Wolverine Outbox 投递 RabbitMQ，至少一次语义。
- 消费端幂等（Inbox 表 / 唯一键）保证不重复处理。
- Saga 编排跨聚合流程，补偿失败分支。

### 数据库隔离

每个模块使用独立 Schema，`DbContext` 只映射自己的 Schema：

~~~csharp
builder.HasDefaultSchema("ordering");
~~~

### 跨模块通信

**异步（主要方式）：** 通过 `FreshMart.Shared.Contracts` 中的集成事件。

**同步（少量场景）：** 通过 `Application/Abstractions/` 中的接口。单体阶段用进程内实现，微服务阶段换 HTTP/gRPC，应用层代码零改动。

### 模块注册

每个模块提供统一入口 `AddXxxInfrastructure` + `MapXxxEndpoints`，宿主只做聚合。

---

## 测试

~~~bash
dotnet test                                    # 全部
dotnet test tests/FreshMart.Catalog.Tests      # 单元
dotnet test tests/FreshMart.IntegrationTests   # 集成（Testcontainers）
dotnet test tests/FreshMart.ArchitectureTests  # 架构
~~~

### 架构测试规则

- `FreshMart.Shared.Core` 不依赖任何其他项目。
- `FreshMart.{X}.Domain` 的 csproj 只引用 `Shared.Core`。
- `FreshMart.{X}.Application` 不依赖同模块的 `Infrastructure`。
- `FreshMart.{X}.Api` 不依赖同模块的 `Infrastructure`。
- 模块之间不互相引用。

---

## 部署

### Docker / Podman

~~~bash
cd deploy/docker
podman compose up -d --build
~~~

### Kubernetes

~~~bash
kubectl apply -f deploy/k8s/namespace.yaml
kubectl apply -f deploy/k8s/postgres-statefulset.yaml
kubectl apply -f deploy/k8s/redis-deployment.yaml
kubectl apply -f deploy/k8s/rabbitmq-deployment.yaml
kubectl apply -f deploy/k8s/elasticsearch-statefulset.yaml
kubectl apply -f deploy/k8s/otel-collector-deployment.yaml
kubectl apply -f deploy/k8s/api-deployment.yaml
kubectl apply -f deploy/k8s/worker-deployment.yaml
kubectl apply -f deploy/k8s/ingress.yaml
~~~

---

## 拆分微服务路线

| 单体 | 微服务 | 改动 |
|---|---|---|
| `src/Catalog/` | 独立仓库/解决方案 | 复制目录 |
| `FreshMart.Shared.*` | NuGet 包 | 发版 |
| `FreshMart.Shared.Contracts` | NuGet 包 | 发版 |
| 模块内的 Schema | 独立数据库 | 导出 |
| `InProcessPaymentClient` | `HttpPaymentClient` | 换实现 |
| `AddCatalogInfrastructure` | 新服务 `Program.cs` | 搬过去 |
| `MapCatalogEndpoints` | 新服务 `Program.cs` | 搬过去 |

**业务代码（Domain + Application）零改动。**

### 拆分前提（五条底线）

1. 模块之间只通过集成事件 + ID 引用通信。
2. 每个模块有自己的 Schema，不跨模块 Join。
3. 一次事务只改一个模块的数据。
4. Outbox 表和业务表在同一 Schema、同一事务。
5. 跨模块调用通过接口抽象，单体用进程内实现。

---

## License

[MIT](LICENSE)

---

## 参考

- [.NET 10 文档](https://learn.microsoft.com/dotnet/)
- [Wolverine 文档](https://wolverinefx.net/)
- [Metalama 文档](https://doc.metalama.net/)
- [OpenTelemetry .NET](https://opentelemetry.io/docs/languages/net/)
- [.NET Aspire Dashboard](https://learn.microsoft.com/dotnet/aspire/fundamentals/dashboard/standalone)
- [Vertical Slice Architecture](https://www.youtube.com/watch?v=SUiWfhAhgQw) — Jimmy Bogard
- [Modular Monolith with DDD](https://github.com/kgrzybek/modular-monolith-with-ddd) — Kamil Grzybek

