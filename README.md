# FreshMart · 同城生鲜履约系统

> 一个基于 .NET 9 + Minimal API + 垂直切片 + 整洁架构 + DDD + 事件驱动的同城生鲜电商履约系统。

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
- [快速开始](#快速开始)
- [关键设计](#关键设计)
- [测试](#测试)
- [部署](#部署)
- [Roadmap](#roadmap)
- [License](#license)

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

```
PendingPayment ──► Paid ──► Preparing ──► Delivering ──► Completed
      │              │
      ▼              ▼
  Cancelled      Refunding ──► Cancelled
```

---

## 技术栈

| 层次 | 技术 |
|---|---|
| 语言/框架 | .NET 9、ASP.NET Core Minimal API |
| 架构模式 | 垂直切片、整洁架构、DDD、CQRS、事件驱动 |
| 进程内分发 | Mediator.SourceGenerator |
| 集成事件 | Wolverine + RabbitMQ（Outbox、Saga、重试、死信） |
| AOP | Metalama（日志、事务、缓存、幂等、审计、重试、验证） |
| 数据库 | PostgreSQL 16 |
| 缓存/锁 | Redis 7 |
| 消息 | RabbitMQ 3.13 |
| 搜索 | Elasticsearch 8.x |
| 部署 | Podman / Docker、Kubernetes、Nginx |
| 测试 | xUnit、FluentAssertions、Testcontainers、NetArchTest |

---

## 架构概览

```
┌─────────────────────────────────────────────────────────────┐
│                       Nginx (Ingress)                        │
│              /api  /kibana  /rabbitmq                        │
└──────────────┬──────────────────────────────┬───────────────┘
               │                              │
        ┌──────▼──────┐                ┌──────▼──────┐
        │ FreshMart   │                │ FreshMart   │
        │    .Api     │                │  .Worker    │
        │ (Minimal    │                │ (Consumers) │
        │  API + VS)  │                │             │
        └──────┬──────┘                └──────┬──────┘
               │                              │
       ┌───────┴──────────┬───────────────────┘
       │                  │
┌──────▼──────┐   ┌───────▼──────┐   ┌──────────────┐
│ PostgreSQL  │   │    Redis     │   │  RabbitMQ    │
│ (写模型+    │   │ (缓存/锁/    │   │ (集成事件+   │
│  Outbox)    │   │  幂等键)     │   │  Saga)       │
└─────────────┘   └──────────────┘   └──────┬───────┘
                                             │
                                      ┌──────▼───────┐
                                      │Elasticsearch │
                                      │(搜索+审计)   │
                                      └──────────────┘
```

依赖方向：

```
Api / Worker ──► Infrastructure ──► Application ──► Domain
```

- **Domain**：零外部依赖，聚合、值对象、领域事件、仓储接口。
- **Application**：用例编排、命令/查询、Saga、集成事件契约。
- **Infrastructure**：EF Core、Redis、RabbitMQ、Elasticsearch 实现。
- **Api**：Minimal API 端点，按垂直切片组织。
- **Worker**：后台消费者、搜索索引同步、超时检查。

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

---

## 核心流程

### 流程 A：商品上架与搜索

```
商家 POST /api/products
  └─► Features/Catalog/CreateProduct 端点
       └─► Mediator 分发 CreateProductCommand
            └─► 创建 Product 聚合，发布 ProductCreated
                 └─► Wolverine Outbox 发 ProductChangedIntegrationEvent 到 RabbitMQ
                      └─► Search Worker 消费，写 Elasticsearch

用户 GET /api/products/search?q=牛奶
  └─► 查询走 Elasticsearch
用户 GET /api/products/{id}
  └─► 先读 Redis，未命中再读 PostgreSQL
```

### 流程 B：下单、库存预占、支付、确认

```
POST /api/orders
  └─► PlaceOrderCommand 校验购物车、地址、商品状态
       └─► 库存上下文预占：Redis 锁 + PostgreSQL 事务
            └─► 创建 Order（PendingPayment），发布 OrderPlaced
                 └─► OrderFulfillmentSaga 启动，等待 InventoryReserved + PaymentSucceeded

POST /api/payments/callback
  └─► 支付上下文幂等处理，发布 PaymentSucceeded
       └─► Saga 收到两个事件 → ConfirmOrderCommand → 扣减库存 → OrderConfirmed
            └─► 配送上下文创建 DeliveryTask，通知骑手
                 └─► 骑手接单、取货、送达 → DeliveryCompleted
                      └─► 订单 Completed，通知用户，审计写 ES
```

### 流程 C：支付超时取消

```
下单时 Wolverine 延时消息 15 分钟后检查
  └─► 若仍未支付 → CancelOrderCommand
       └─► OrderCancelled → 库存释放 → 通知用户 → 审计记录
```

### 流程 D：库存不足或支付失败

```
库存预占失败 → InventoryReservationFailed
  └─► Saga 取消订单，若已支付则发起模拟退款
       └─► 通知用户，释放相关资源
```

---

## 解决方案结构

```
FreshMart/
├── src/
│   ├── FreshMart.Domain/            # 领域层（零依赖）
│   ├── FreshMart.Application/       # 应用层（用例、Saga、契约）
│   ├── FreshMart.Infrastructure/    # 基础设施（EF、Redis、MQ、ES）
│   ├── FreshMart.Api/               # Minimal API（垂直切片）
│   └── FreshMart.Worker/            # 后台消费者
├── tests/
│   ├── FreshMart.UnitTests/
│   ├── FreshMart.IntegrationTests/
│   └── FreshMart.ArchitectureTests/
├── deploy/
│   ├── docker/
│   ├── k8s/
│   └── nginx/
├── Directory.Build.props
├── Directory.Packages.props
└── FreshMart.sln
```

---

## 快速开始

### 前置条件

- [.NET 9 SDK](https://dotnet.microsoft.com/download/dotnet/9.0)
- [Podman](https://podman.io/) 或 [Docker](https://www.docker.com/)
- （可选）[kubectl](https://kubernetes.io/docs/tasks/tools/) + [kind](https://kind.sigs.k8s.io/) 或 [minikube](https://minikube.sigs.k8s.io/)

### 1. 克隆仓库

```bash
git clone https://github.com/yourname/FreshMart.git
cd FreshMart
```

### 2. 启动依赖中间件

```bash
cd deploy/docker
podman compose up -d
# 或
docker compose up -d
```

启动的服务：

| 服务 | 端口 | 说明 |
|---|---|---|
| PostgreSQL | 5432 | 主库 |
| Redis | 6379 | 缓存 / 锁 / 幂等键 |
| RabbitMQ | 5672 / 15672 | 消息队列 / 管理台 |
| Elasticsearch | 9200 | 搜索 / 审计 |
| Kibana | 5601 | ES 可视化 |

### 3. 应用数据库迁移

```bash
dotnet ef database update \
  --project src/FreshMart.Infrastructure \
  --startup-project src/FreshMart.Api
```

### 4. 启动 API 与 Worker

```bash
# 终端 1
dotnet run --project src/FreshMart.Api

# 终端 2
dotnet run --project src/FreshMart.Worker
```

访问：

- API Swagger：http://localhost:5000/swagger
- RabbitMQ 管理台：http://localhost:15672 （guest / guest）
- Kibana：http://localhost:5601

### 5. 一键启动全部（可选）

```bash
podman compose -f deploy/docker/docker-compose.yml up -d --build
```

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
- Redis 幂等键 `idem:payment:{paymentId}` 做前置拦截。

### 最终一致

- 写模型与 Outbox 在同一 PostgreSQL 事务。
- Wolverine Outbox 投递 RabbitMQ，至少一次语义。
- 消费端幂等（Inbox 表 / 唯一键）保证不重复处理。
- Saga 编排跨聚合流程，补偿失败分支。

### 搜索索引同步

- `ProductChangedIntegrationEvent` 由 Search Worker 消费。
- ES 文档以 `ProductId` 为 `_id`，重复消费幂等 upsert。
- 失败重试 → 死信队列 → 人工/定时补偿。

---

## 测试

```bash
# 全部测试
dotnet test

# 单元测试
dotnet test tests/FreshMart.UnitTests

# 集成测试（依赖 Testcontainers，需本地有 Podman/Docker）
dotnet test tests/FreshMart.IntegrationTests

# 架构测试（验证依赖方向）
dotnet test tests/FreshMart.ArchitectureTests

# 覆盖率
dotnet test /p:CollectCoverage=true /p:CoverletOutputFormat=opencover
```

---

## 部署

### Docker / Podman

```bash
cd deploy/docker
podman compose up -d --build
```

### Kubernetes

```bash
kubectl apply -f deploy/k8s/namespace.yaml
kubectl apply -f deploy/k8s/postgres-statefulset.yaml
kubectl apply -f deploy/k8s/redis-deployment.yaml
kubectl apply -f deploy/k8s/rabbitmq-deployment.yaml
kubectl apply -f deploy/k8s/elasticsearch-statefulset.yaml
kubectl apply -f deploy/k8s/api-deployment.yaml
kubectl apply -f deploy/k8s/worker-deployment.yaml
kubectl apply -f deploy/k8s/ingress.yaml
```

Nginx Ingress 路由：

| 路径 | 后端 |
|---|---|
| `/api` | `freshmart-api:80` |
| `/kibana` | `kibana:5601` |
| `/rabbitmq` | `rabbitmq-management:15672` |

---

## Roadmap

- [x] 领域建模：Ordering / Inventory / Payment / Delivery / Catalog
- [x] Outbox + RabbitMQ 集成事件
- [x] 库存预占 + 乐观并发 + Redis 锁
- [x] 支付回调幂等
- [x] 订单状态机 + Saga 编排
- [x] Elasticsearch 搜索索引同步
- [x] 审计日志写 ES
- [ ] 购物车上下文完整实现
- [ ] 通知上下文（短信/推送）
- [ ] 评价与售后
- [ ] 压测报告（JMeter / k6）
- [ ] OpenTelemetry + Jaeger 链路追踪
- [ ] Grafana + Prometheus 监控面板

---

## License

[MIT](LICENSE)

---

## 参考

- [.NET 9 文档](https://learn.microsoft.com/dotnet/)
- [Wolverine 文档](https://wolverinefx.net/)
- [Mediator.SourceGenerator](https://github.com/martinothamar/Mediator)
- [Metalama 文档](https://doc.metalama.net/)
- [Vertical Slice Architecture](https://www.youtube.com/watch?v=SUiWfhAhgQw) — Jimmy Bogard
- [Domain-Driven Design Reference](https://domainlanguage.com/ddd/reference/) — Eric Evans
