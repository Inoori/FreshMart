#!/usr/bin/env bash
# scripts/setup-github-project.sh
# ============================================================
# FreshMart GitHub Projects 一键配置脚本
#
# 功能：
#   1. 环境检查（gh CLI、认证、scope）
#   2. 创建/复用 GitHub Project
#   3. 创建自定义字段（Priority / Category / Layer / Module）
#   4. 创建标签（层 / 模块 / 优先级 / 类型）
#   5. 创建里程碑（M0~M9）
#   6. 批量创建 Issue 并加入 Project
#   7. 输出手动操作指引
#
# 幂等：可反复执行，已存在的自动跳过
#
# 前置条件：
#   1. gh CLI 已安装并认证
#   2. gh auth refresh -s project,read:project,repo,workflow,read:org
#   3. 已 cd 到项目根目录
#
# 用法：
#   chmod +x scripts/setup-github-project.sh
#   ./scripts/setup-github-project.sh
# ============================================================

set -uo pipefail

# ============================================================
# 配置（按需修改这 3 个变量）
# ============================================================
OWNER="Inoori"
REPO="Inoori/FreshMart"
PROJECT_TITLE="FreshMart 开发计划"

# ============================================================
# 辅助函数
# ============================================================
info()    { echo "  $*"; }
success() { echo "  ✅ $*"; }
skip()    { echo "  ⏭️  $*"; }
error()   { echo "  ❌ $*" >&2; }

FIELD_SUCCESS=0; FIELD_FAILED=0; FIELD_SKIPPED=0
LABEL_SUCCESS=0; LABEL_FAILED=0; LABEL_SKIPPED=0
MS_SUCCESS=0;    MS_FAILED=0;    MS_SKIPPED=0
ISSUE_SUCCESS=0; ISSUE_FAILED=0; ISSUE_SKIPPED=0

# ============================================================
# 0. 环境检查
# ============================================================
echo "=== 0. 环境检查 ==="

if ! command -v gh &>/dev/null; then
  error "未找到 gh CLI，请先安装：https://cli.github.com/"
  exit 1
fi

if ! gh auth status &>/dev/null; then
  error "gh 未认证，请执行：gh auth login"
  exit 1
fi

SCOPES=$(gh auth status 2>&1 | grep -oE "Token scopes:.*" || true)
if [[ "$SCOPES" != *"project"* ]]; then
  error "缺少 project scope，请执行："
  error "  gh auth refresh -s project,read:project,repo,workflow,read:org"
  exit 1
fi

success "gh CLI 已就绪"

# ============================================================
# 1. 创建 Project
# ============================================================
echo ""
echo "=== 1. 创建 Project ==="

PROJECT_NUMBER=$(gh project list --owner "$OWNER" --format json \
  --jq ".projects[] | select(.title == \"$PROJECT_TITLE\") | .number" 2>/dev/null || echo "")

if [[ -n "$PROJECT_NUMBER" ]]; then
  skip "Project 已存在：#$PROJECT_NUMBER"
else
  PROJECT_URL=$(gh project create --owner "$OWNER" --title "$PROJECT_TITLE" 2>&1 | tail -1)
  PROJECT_NUMBER=$(echo "$PROJECT_URL" | grep -oE '[0-9]+$' || true)
  success "创建 Project：#$PROJECT_NUMBER"
fi

if [[ -z "$PROJECT_NUMBER" ]]; then
  error "无法获取 Project 编号"
  exit 1
fi

echo "  Project 编号：$PROJECT_NUMBER"

# ============================================================
# 2. 创建自定义字段
# ============================================================
echo ""
echo "=== 2. 创建自定义字段 ==="

EXISTING_FIELDS=$(gh api graphql -f query='
query($owner: String!, $number: Int!) {
  user(login: $owner) {
    projectV2(number: $number) {
      fields(first: 100) {
        nodes {
          ... on ProjectV2FieldCommon { name }
        }
      }
    }
  }
}' -f owner="$OWNER" -F number="$PROJECT_NUMBER" \
  --jq '.data.user.projectV2.fields.nodes[].name' 2>/dev/null || echo "")

create_field() {
  local name="$1" options="$2"

  if echo "$EXISTING_FIELDS" | grep -Fxq "$name"; then
    skip "字段：$name"
    FIELD_SKIPPED=$((FIELD_SKIPPED + 1))
    return 0
  fi

  local output
  if output=$(gh project field-create "$PROJECT_NUMBER" --owner "$OWNER" \
       --name "$name" --data-type "SINGLE_SELECT" \
       --single-select-options "$options" 2>&1); then
    success "字段：$name"
    FIELD_SUCCESS=$((FIELD_SUCCESS + 1))
  else
    error "字段失败：$name"
    echo "$output" | head -3 | sed 's/^/     /'
    FIELD_FAILED=$((FIELD_FAILED + 1))
  fi
}

create_field "Priority" "P0 (Critical),P1 (High),P2 (Medium),P3 (Low)"
create_field "Category" "Feature,Bug,Chore,Docs,Refactor"
create_field "Layer"    "Domain,Application,Infrastructure,Api,Shared"
create_field "Module"   "Catalog,Inventory,Cart,Ordering,Payment,Delivery,Notification,Search,Audit,Identity,Shared"

# ============================================================
# 3. 创建标签
# ============================================================
echo ""
echo "=== 3. 创建标签 ==="

EXISTING_LABELS=$(gh label list --repo "$REPO" --limit 200 --json name --jq '.[].name' 2>/dev/null || echo "")

create_label() {
  local name="$1" color="$2"

  if echo "$EXISTING_LABELS" | grep -Fxq "$name"; then
    skip "标签：$name"
    LABEL_SKIPPED=$((LABEL_SKIPPED + 1))
    return 0
  fi

  local output
  if output=$(gh label create "$name" --color "$color" --repo "$REPO" 2>&1); then
    success "标签：$name"
    LABEL_SUCCESS=$((LABEL_SUCCESS + 1))
  else
    error "标签失败：$name"
    echo "$output" | head -3 | sed 's/^/     /'
    LABEL_FAILED=$((LABEL_FAILED + 1))
  fi
}

# 层标签
create_label "layer/domain"         "1D76DB"
create_label "layer/application"    "5319E7"
create_label "layer/infrastructure" "0E8A16"
create_label "layer/api"            "FBCA04"
create_label "layer/shared"         "C5DEF5"

# 模块标签
for m in shared catalog inventory cart ordering payment delivery notification search audit identity; do
  create_label "module/$m" "BFD4F2"
done

# 优先级标签
create_label "priority/p0" "B60205"
create_label "priority/p1" "D93F0B"
create_label "priority/p2" "FBCA04"
create_label "priority/p3" "0E8A16"

# 类型标签
create_label "type/feature"  "A2EEEF"
create_label "type/bug"      "D73A4A"
create_label "type/chore"    "FEF2C0"
create_label "type/docs"     "0075CA"
create_label "type/refactor" "D4C5F9"

# ============================================================
# 4. 创建里程碑
# ============================================================
echo ""
echo "=== 4. 创建里程碑 ==="

EXISTING_MILESTONES=$(gh api "repos/$REPO/milestones?state=all&per_page=100" \
  --paginate --jq '.[].title' 2>/dev/null || echo "")

create_milestone() {
  local title="$1" desc="$2"

  if echo "$EXISTING_MILESTONES" | grep -Fxq "$title"; then
    skip "里程碑：$title"
    MS_SKIPPED=$((MS_SKIPPED + 1))
    return 0
  fi

  local output
  if output=$(gh api "repos/$REPO/milestones" \
       -f title="$title" -f description="$desc" 2>&1); then
    success "里程碑：$title"
    MS_SUCCESS=$((MS_SUCCESS + 1))
  else
    error "里程碑失败：$title"
    echo "$output" | head -3 | sed 's/^/     /'
    MS_FAILED=$((MS_FAILED + 1))
  fi
}

create_milestone "M0: 骨架与开发环境就绪" "项目能构建、依赖能启动、可观测性可见"
create_milestone "M1: BuildingBlocks 完成" "共享基元可复用，单元测试通过"
create_milestone "M2: Catalog 打通"       "商品上架 → 事件 → ES 索引 → 搜索"
create_milestone "M3: 订单与库存 MVP"     "下单 → 预占 → 支付 → 确认"
create_milestone "M4: 履约闭环"           "配送任务 → 接单 → 完成；订单 Completed"
create_milestone "M5: 异常与一致性"       "超时取消、库存不足、支付失败、幂等、并发不超卖"
create_milestone "M6: 辅助模块"           "Cart / Notification / Audit / Identity / Search"
create_milestone "M7: 生产就绪"           "部署 + 可观测性完善 + 测试覆盖"
create_milestone "M8: 稳定性验证"         "压测 + 故障演练"
create_milestone "M9: 微服务拆分（可选）" "按模块拆服务，独立部署"

# ============================================================
# 5. 批量创建 Issue
# ============================================================
echo ""
echo "=== 5. 批量创建 Issue ==="

EXISTING_TITLES=$(gh issue list --repo "$REPO" --state all --limit 500 \
  --json title --jq '.[].title' 2>/dev/null || echo "")

create_issue() {
  local title="$1" body="$2" milestone="$3" labels="$4"

  if echo "$EXISTING_TITLES" | grep -Fxq "$title"; then
    skip "$title"
    ISSUE_SKIPPED=$((ISSUE_SKIPPED + 1))
    return 0
  fi

  local output exit_code=0
  output=$(gh issue create \
    --repo "$REPO" --title "$title" --body "$body" \
    --milestone "$milestone" --label "$labels" 2>&1) || exit_code=$?

  if [[ $exit_code -ne 0 ]]; then
    error "$title"
    echo "$output" | head -3 | sed 's/^/     /'
    ISSUE_FAILED=$((ISSUE_FAILED + 1))
    return 1
  fi

  local issue_url
  issue_url=$(echo "$output" | grep -oE 'https://github.com/[^ ]+/issues/[0-9]+' | tail -1 || true)

  if [[ -z "$issue_url" ]]; then
    error "$title (未解析到 URL)"
    ISSUE_FAILED=$((ISSUE_FAILED + 1))
    return 1
  fi

  gh project item-add "$PROJECT_NUMBER" --owner "$OWNER" --url "$issue_url" >/dev/null 2>&1 || true
  success "$title"
  ISSUE_SUCCESS=$((ISSUE_SUCCESS + 1))
  return 0
}

# ------------------------------------------------------------
# M0: 骨架与开发环境就绪
# ------------------------------------------------------------
echo ""
echo "--- M0: 骨架与开发环境就绪 ---"

create_issue "[M0.1] 运行 create-freshmart.sh 确认骨架" \
  "运行脚本，确认所有项目创建成功，dotnet build 通过" \
  "M0: 骨架与开发环境就绪" "type/chore,priority/p0"

create_issue "[M0.2] 检查全局配置文件" \
  "Directory.Build.props / Directory.Packages.props / .editorconfig / .gitattributes / .gitignore" \
  "M0: 骨架与开发环境就绪" "type/chore,priority/p1"

create_issue "[M0.3] 首次 Git 提交建立基线" \
  "git add . && git commit -m 'chore: initial scaffold'" \
  "M0: 骨架与开发环境就绪" "type/chore,priority/p0"

create_issue "[M0.4] 编写 docker-compose.yml" \
  "PostgreSQL + Redis + RabbitMQ + Elasticsearch + Kibana + Aspire Dashboard + EDOT Collector" \
  "M0: 骨架与开发环境就绪" "type/chore,priority/p0"

create_issue "[M0.5] 编写 otel-collector.yml" \
  "EDOT Collector 配置，接收 OTLP 写入 Elasticsearch" \
  "M0: 骨架与开发环境就绪" "type/chore,priority/p0"

create_issue "[M0.6] Api 宿主接入 OpenTelemetry" \
  "AddOpenTelemetry + UseOtlpExporter，配置 AspNetCore / HttpClient / EF Core / Wolverine" \
  "M0: 骨架与开发环境就绪" "type/chore,priority/p0"

create_issue "[M0.7] Worker 宿主接入 OpenTelemetry" \
  "同上，Worker 侧重 Wolverine 和 EF Core" \
  "M0: 骨架与开发环境就绪" "type/chore,priority/p0"

create_issue "[M0.8] 验证 Aspire Dashboard 能收到 trace" \
  "启动 Api，访问任意端点，Dashboard 显示 trace" \
  "M0: 骨架与开发环境就绪" "type/chore,priority/p0"

create_issue "[M0.9] 创建多 Schema 初始化脚本" \
  "catalog / inventory / cart / ordering / payment / delivery / identity" \
  "M0: 骨架与开发环境就绪" "type/chore,priority/p0"

# ------------------------------------------------------------
# M1: BuildingBlocks 完成
# ------------------------------------------------------------
echo ""
echo "--- M1: BuildingBlocks 完成 ---"

create_issue "[M1.1] Entity 基类" \
  "FreshMart.Shared.Core/Domain/Entity.cs，含 Id 和 DomainEvents" \
  "M1: BuildingBlocks 完成" "layer/domain,module/shared,priority/p0"

create_issue "[M1.2] AggregateRoot 基类" \
  "继承 Entity<TId>，加入 Version 乐观并发字段" \
  "M1: BuildingBlocks 完成" "layer/domain,module/shared,priority/p0"

create_issue "[M1.3] ValueObject 基类" \
  "GetEqualityComponents、Equals、GetHashCode、== / !=" \
  "M1: BuildingBlocks 完成" "layer/domain,module/shared,priority/p0"

create_issue "[M1.4] IDomainEvent 和 DomainException" \
  "IDomainEvent 含 EventId 和 OccurredAt" \
  "M1: BuildingBlocks 完成" "layer/domain,module/shared,priority/p0"

create_issue "[M1.5] Money 值对象" \
  "Amount、Currency，支持 +、* 运算符，金额不能为负" \
  "M1: BuildingBlocks 完成" "layer/domain,module/shared,priority/p0"

create_issue "[M1.6] Address 值对象" \
  "Province、City、District、Detail、ReceiverName、ReceiverPhone" \
  "M1: BuildingBlocks 完成" "layer/domain,module/shared,priority/p0"

create_issue "[M1.7] Result / Result<T> / Error" \
  "应用层返回结果，避免抛异常" \
  "M1: BuildingBlocks 完成" "layer/application,module/shared,priority/p1"

create_issue "[M1.8] Guard 工具类" \
  "NotNull、NotEmpty、GreaterThan 等" \
  "M1: BuildingBlocks 完成" "layer/domain,module/shared,priority/p2"

create_issue "[M1.9] IClock / ICurrentUser / IUnitOfWork" \
  "横切抽象，领域层和应用层共用" \
  "M1: BuildingBlocks 完成" "layer/domain,module/shared,priority/p1"

create_issue "[M1.10] 强类型 ID 转换器" \
  "StronglyTypedIdConverter<TId, TValue>，配合 EF Core HasConversion" \
  "M1: BuildingBlocks 完成" "layer/infrastructure,module/shared,priority/p1"

create_issue "[M1.11] EntityTypeBuilder 扩展" \
  "HasStronglyTypedId、UseFieldAccess、IsAggregateVersion" \
  "M1: BuildingBlocks 完成" "layer/infrastructure,module/shared,priority/p1"

create_issue "[M1.12] ModelBuilder 扩展" \
  "UseSnakeCaseNaming 统一命名规范" \
  "M1: BuildingBlocks 完成" "layer/infrastructure,module/shared,priority/p2"

create_issue "[M1.13] OutboxMessage 实体和配置" \
  "Outbox 表和业务表在同一事务，保证事件不丢" \
  "M1: BuildingBlocks 完成" "layer/infrastructure,module/shared,priority/p0"

create_issue "[M1.14] InboxMessage 实体和配置" \
  "消费端幂等，防止重复处理" \
  "M1: BuildingBlocks 完成" "layer/infrastructure,module/shared,priority/p0"

create_issue "[M1.15] AuditableEntityInterceptor" \
  "自动填充 CreatedAt / UpdatedAt" \
  "M1: BuildingBlocks 完成" "layer/infrastructure,module/shared,priority/p2"

create_issue "[M1.16] Wolverine 基础扩展" \
  "AddFreshMartMessaging 扩展方法，统一 Wolverine 配置" \
  "M1: BuildingBlocks 完成" "layer/infrastructure,module/shared,priority/p0"

create_issue "[M1.17] Outbox / Inbox 与 EF Core 集成" \
  "Wolverine 的 Outbox / Inbox 与 EF Core 集成" \
  "M1: BuildingBlocks 完成" "layer/infrastructure,module/shared,priority/p0"

create_issue "[M1.18] 重试策略和死信" \
  "指数退避重试，超过次数进死信队列" \
  "M1: BuildingBlocks 完成" "layer/infrastructure,module/shared,priority/p1"

create_issue "[M1.19] Mediator ValidationBehavior" \
  "命令进入 Handler 前自动验证，失败抛 ValidationException" \
  "M1: BuildingBlocks 完成" "layer/application,module/shared,priority/p0"

create_issue "[M1.20] 通用验证扩展" \
  "手机号格式、地址完整性等" \
  "M1: BuildingBlocks 完成" "layer/application,module/shared,priority/p1"

create_issue "[M1.21] IEndpoint 接口和自动注册" \
  "IEndpoint + EndpointRouteBuilderExtensions，扫描程序集自动注册" \
  "M1: BuildingBlocks 完成" "layer/api,module/shared,priority/p0"

create_issue "[M1.22] Result → IResult 转换" \
  "ResultExtensions.ToIResult()，Result 映射为 HTTP 响应" \
  "M1: BuildingBlocks 完成" "layer/api,module/shared,priority/p0"

create_issue "[M1.23] 全局异常处理中间件" \
  "捕获 DomainException、ValidationException，返回 ProblemDetails" \
  "M1: BuildingBlocks 完成" "layer/api,module/shared,priority/p0"

create_issue "[M1.24] 授权策略和 RequireRole 扩展" \
  "Consumer / Merchant / Rider / Operator 四种策略" \
  "M1: BuildingBlocks 完成" "layer/api,module/shared,priority/p1"

create_issue "[M1.25] IIntegrationEvent 基接口" \
  "所有集成事件的基接口" \
  "M1: BuildingBlocks 完成" "layer/shared,module/shared,priority/p1"

create_issue "[M1.26] Shared.Core 单元测试" \
  "Entity、ValueObject、Money、Result 核心行为" \
  "M1: BuildingBlocks 完成" "type/chore,module/shared,priority/p0"

# ------------------------------------------------------------
# M2: Catalog 打通
# ------------------------------------------------------------
echo ""
echo "--- M2: Catalog 打通 ---"

create_issue "[M2.1] Product 聚合根" \
  "含 Name、Description、Category、Status、Skus 集合" \
  "M2: Catalog 打通" "layer/domain,module/catalog,priority/p0"

create_issue "[M2.2] Sku 实体和 ProductStatus 值对象" \
  "Sku 含 Name、Price、Unit" \
  "M2: Catalog 打通" "layer/domain,module/catalog,priority/p0"

create_issue "[M2.3] Catalog 领域事件" \
  "ProductCreated / ProductPriceChanged / ProductOnShelf / ProductOffShelf" \
  "M2: Catalog 打通" "layer/domain,module/catalog,priority/p0"

create_issue "[M2.4] IProductRepository 接口" \
  "Application/Abstractions 中定义" \
  "M2: Catalog 打通" "layer/application,module/catalog,priority/p0"

create_issue "[M2.5] CreateProduct 用例" \
  "Features/CreateProduct/，Command + Handler + Validator" \
  "M2: Catalog 打通" "layer/application,module/catalog,priority/p0"

create_issue "[M2.6] ChangePrice / OnShelf / OffShelf 用例" \
  "Features/ChangePrice/、OnShelf/、OffShelf/" \
  "M2: Catalog 打通" "layer/application,module/catalog,priority/p0"

create_issue "[M2.7] GetProduct / SearchProducts 查询" \
  "Features/GetProduct/、SearchProducts/" \
  "M2: Catalog 打通" "layer/application,module/catalog,priority/p0"

create_issue "[M2.8] CatalogDbContext" \
  "Schema 为 catalog，映射 Product / Sku / Outbox" \
  "M2: Catalog 打通" "layer/infrastructure,module/catalog,priority/p0"

create_issue "[M2.9] EF Core 配置" \
  "ProductConfiguration + SkuConfiguration + OutboxConfiguration" \
  "M2: Catalog 打通" "layer/infrastructure,module/catalog,priority/p0"

create_issue "[M2.10] ProductRepository 实现" \
  "实现 IProductRepository" \
  "M2: Catalog 打通" "layer/infrastructure,module/catalog,priority/p0"

create_issue "[M2.11] Redis 商品缓存" \
  "ProductCache，先读 Redis 未命中再读 PostgreSQL" \
  "M2: Catalog 打通" "layer/infrastructure,module/catalog,priority/p1"

create_issue "[M2.12] CatalogModule 注册入口" \
  "AddCatalogInfrastructure + MapCatalogEndpoints" \
  "M2: Catalog 打通" "layer/infrastructure,module/catalog,priority/p0"

create_issue "[M2.13] CreateProduct 端点" \
  "Api/Features/CreateProduct/CreateProductEndpoint" \
  "M2: Catalog 打通" "layer/api,module/catalog,priority/p0"

create_issue "[M2.14] SearchProducts 端点" \
  "Api/Features/SearchProducts/" \
  "M2: Catalog 打通" "layer/api,module/catalog,priority/p0"

create_issue "[M2.15] GetProduct 端点" \
  "Api/Features/GetProduct/" \
  "M2: Catalog 打通" "layer/api,module/catalog,priority/p0"

create_issue "[M2.16] Search Worker 消费 ProductChangedIntegrationEvent" \
  "Consumers/ProductChangedConsumer，写入 Elasticsearch" \
  "M2: Catalog 打通" "layer/infrastructure,module/search,priority/p0"

create_issue "[M2.17] 端到端验证：上架 → 事件 → ES → 搜索" \
  "商家调用 POST /api/catalog/products，验证链路完整" \
  "M2: Catalog 打通" "type/feature,module/catalog,priority/p0"

create_issue "[M2.18] Catalog 领域测试" \
  "Product 状态转换、价格变更" \
  "M2: Catalog 打通" "type/chore,module/catalog,priority/p0"

# ------------------------------------------------------------
# M3: 订单与库存 MVP
# ------------------------------------------------------------
echo ""
echo "--- M3: 订单与库存 MVP ---"

# Inventory
create_issue "[M3.1] InventoryItem 聚合根" \
  "含 StoreId、SkuId、Available、Reserved" \
  "M3: 订单与库存 MVP" "layer/domain,module/inventory,priority/p0"

create_issue "[M3.2] Reserve / Release / Deduct 领域方法" \
  "预占扣 Available 增 Reserved；释放反向；扣减只减 Reserved" \
  "M3: 订单与库存 MVP" "layer/domain,module/inventory,priority/p0"

create_issue "[M3.3] Inventory 领域事件" \
  "InventoryReserved / InventoryReleased / InventoryDeducted" \
  "M3: 订单与库存 MVP" "layer/domain,module/inventory,priority/p0"

create_issue "[M3.4] IInventoryRepository 接口" \
  "含 GetByStoreAndSku" \
  "M3: 订单与库存 MVP" "layer/application,module/inventory,priority/p0"

create_issue "[M3.5] ReserveInventory / ReleaseInventory / DeductInventory 用例" \
  "Features/ReserveInventory/、ReleaseInventory/、DeductInventory/" \
  "M3: 订单与库存 MVP" "layer/application,module/inventory,priority/p0"

create_issue "[M3.6] Redis 分布式锁" \
  "lock:inventory:{storeId}:{skuId}" \
  "M3: 订单与库存 MVP" "layer/infrastructure,module/inventory,priority/p0"

create_issue "[M3.7] PostgreSQL 条件更新防超卖" \
  "UPDATE ... WHERE available >= @qty" \
  "M3: 订单与库存 MVP" "layer/infrastructure,module/inventory,priority/p0"

create_issue "[M3.8] 15 分钟预占 TTL" \
  "Wolverine 延时消息，超时未支付自动释放" \
  "M3: 订单与库存 MVP" "layer/infrastructure,module/inventory,priority/p0"

create_issue "[M3.9] InventoryDbContext + EF 配置" \
  "Schema 为 inventory，StoreId + SkuId 唯一索引" \
  "M3: 订单与库存 MVP" "layer/infrastructure,module/inventory,priority/p0"

create_issue "[M3.10] InventoryRepository + Module 注册" \
  "实现 IInventoryRepository，AddInventoryInfrastructure" \
  "M3: 订单与库存 MVP" "layer/infrastructure,module/inventory,priority/p0"

create_issue "[M3.11] Inventory 内部 API" \
  "预占 / 释放 / 扣减端点" \
  "M3: 订单与库存 MVP" "layer/api,module/inventory,priority/p0"

# Payment
create_issue "[M3.12] Payment 聚合根" \
  "含 OrderId、Amount、Status、TransactionNo" \
  "M3: 订单与库存 MVP" "layer/domain,module/payment,priority/p0"

create_issue "[M3.13] PaymentStatus 状态机 + 领域事件" \
  "Pending → Succeeded / Failed / TimedOut" \
  "M3: 订单与库存 MVP" "layer/domain,module/payment,priority/p0"

create_issue "[M3.14] MarkSucceeded 幂等" \
  "已成功直接返回 false，不重复发事件" \
  "M3: 订单与库存 MVP" "layer/domain,module/payment,priority/p0"

create_issue "[M3.15] InitiatePayment / ProcessPaymentCallback 用例" \
  "Features/InitiatePayment/、ProcessPaymentCallback/" \
  "M3: 订单与库存 MVP" "layer/application,module/payment,priority/p0"

create_issue "[M3.16] PaymentId 唯一约束 + Redis 幂等键" \
  "idem:payment:{paymentId} 前置拦截，TTL 24h" \
  "M3: 订单与库存 MVP" "layer/infrastructure,module/payment,priority/p0"

create_issue "[M3.17] PaymentDbContext + PaymentRepository" \
  "Schema 为 payment，映射 Payment + Outbox + Inbox" \
  "M3: 订单与库存 MVP" "layer/infrastructure,module/payment,priority/p0"

create_issue "[M3.18] 模拟支付网关" \
  "开发用，随机成功/失败，可配置成功率" \
  "M3: 订单与库存 MVP" "layer/infrastructure,module/payment,priority/p1"

create_issue "[M3.19] PaymentModule 注册 + 回调端点" \
  "AddPaymentInfrastructure + POST /api/payments/callback" \
  "M3: 订单与库存 MVP" "layer/api,module/payment,priority/p0"

# Ordering
create_issue "[M3.20] Order 聚合根" \
  "含 UserId、StoreId、Address、Status、TotalAmount、Items" \
  "M3: 订单与库存 MVP" "layer/domain,module/ordering,priority/p0"

create_issue "[M3.21] OrderItem 实体" \
  "聚合内实体，含 ProductId、SkuId、UnitPrice、Quantity" \
  "M3: 订单与库存 MVP" "layer/domain,module/ordering,priority/p0"

create_issue "[M3.22] OrderStatus 状态机" \
  "PendingPayment → Paid → Preparing → Delivering → Completed；异常分支 Refunding / Cancelled" \
  "M3: 订单与库存 MVP" "layer/domain,module/ordering,priority/p0"

create_issue "[M3.23] Ordering 领域事件" \
  "OrderPlaced / OrderPaid / OrderConfirmed / OrderCancelled / OrderCompleted" \
  "M3: 订单与库存 MVP" "layer/domain,module/ordering,priority/p0"

create_issue "[M3.24] IOrderRepository + IInventoryClient + IPaymentClient 抽象" \
  "跨模块接口，单体用进程内实现" \
  "M3: 订单与库存 MVP" "layer/application,module/ordering,priority/p0"

create_issue "[M3.25] PlaceOrder / ConfirmOrder / CancelOrder 用例" \
  "Features/PlaceOrder/、ConfirmOrder/、CancelOrder/" \
  "M3: 订单与库存 MVP" "layer/application,module/ordering,priority/p0"

create_issue "[M3.26] GetOrder / ListOrders 查询" \
  "Features/GetOrder/、ListOrders/，读模型" \
  "M3: 订单与库存 MVP" "layer/application,module/ordering,priority/p0"

create_issue "[M3.27] OrderFulfillmentSaga" \
  "编排 InventoryReserved + PaymentSucceeded" \
  "M3: 订单与库存 MVP" "layer/application,module/ordering,priority/p0"

create_issue "[M3.28] 超时取消延时消息" \
  "下单时安排 15 分钟后检查，未支付则取消" \
  "M3: 订单与库存 MVP" "layer/application,module/ordering,priority/p0"

create_issue "[M3.29] InProcessInventoryClient / InProcessPaymentClient" \
  "跨模块接口的进程内实现，走 Mediator 分发" \
  "M3: 订单与库存 MVP" "layer/infrastructure,module/ordering,priority/p0"

create_issue "[M3.30] OrderingDbContext + EF 配置" \
  "Schema 为 ordering，映射 Order + OrderItem + Outbox + Inbox + Saga 状态" \
  "M3: 订单与库存 MVP" "layer/infrastructure,module/ordering,priority/p0"

create_issue "[M3.31] OrderRepository + OrderingModule 注册" \
  "实现 IOrderRepository，AddOrderingInfrastructure" \
  "M3: 订单与库存 MVP" "layer/infrastructure,module/ordering,priority/p0"

create_issue "[M3.32] Ordering 端点" \
  "POST /api/orders、GET /api/orders/{id}、POST /api/orders/{id}/cancel" \
  "M3: 订单与库存 MVP" "layer/api,module/ordering,priority/p0"

create_issue "[M3.33] Inventory / Payment / Ordering 领域测试" \
  "预占边界、状态机、幂等 MarkSucceeded、异常分支" \
  "M3: 订单与库存 MVP" "type/chore,module/ordering,priority/p0"

# ------------------------------------------------------------
# M4: 履约闭环
# ------------------------------------------------------------
echo ""
echo "--- M4: 履约闭环 ---"

create_issue "[M4.1] DeliveryTask 聚合根" \
  "含 OrderId、StoreId、Address、RiderId、Status" \
  "M4: 履约闭环" "layer/domain,module/delivery,priority/p0"

create_issue "[M4.2] DeliveryStatus 状态机 + 领域事件" \
  "Pending → Assigned → PickedUp → Completed" \
  "M4: 履约闭环" "layer/domain,module/delivery,priority/p0"

create_issue "[M4.3] AssignTo 唯一接单" \
  "状态 + RiderId 双重保护" \
  "M4: 履约闭环" "layer/domain,module/delivery,priority/p0"

create_issue "[M4.4] IDeliveryTaskRepository 接口" \
  "Application/Abstractions 中定义" \
  "M4: 履约闭环" "layer/application,module/delivery,priority/p0"

create_issue "[M4.5] CreateDeliveryTask / AssignRider / PickUp / Complete 用例" \
  "Features/CreateDeliveryTask/、AssignRider/、PickUp/、Complete/" \
  "M4: 履约闭环" "layer/application,module/delivery,priority/p0"

create_issue "[M4.6] DeliveryDbContext + EF 配置" \
  "Schema 为 delivery，映射 DeliveryTask + Outbox + Inbox" \
  "M4: 履约闭环" "layer/infrastructure,module/delivery,priority/p0"

create_issue "[M4.7] DeliveryTaskRepository + DeliveryModule 注册" \
  "实现 IDeliveryTaskRepository，AddDeliveryInfrastructure" \
  "M4: 履约闭环" "layer/infrastructure,module/delivery,priority/p0"

create_issue "[M4.8] 骑手端点" \
  "POST /api/delivery/tasks/{id}/assign、/pickup、/complete" \
  "M4: 履约闭环" "layer/api,module/delivery,priority/p0"

create_issue "[M4.9] 端到端正常流程验证" \
  "下单 → 预占 → 支付 → 确认 → 配送 → 完成" \
  "M4: 履约闭环" "type/feature,module/ordering,priority/p0"

create_issue "[M4.10] Delivery 领域测试" \
  "唯一接单、状态转换" \
  "M4: 履约闭环" "type/chore,module/delivery,priority/p0"

# ------------------------------------------------------------
# M5: 异常与一致性
# ------------------------------------------------------------
echo ""
echo "--- M5: 异常与一致性 ---"

create_issue "[M5.1] 支付超时取消验证" \
  "15 分钟未支付自动取消，库存释放" \
  "M5: 异常与一致性" "type/feature,module/ordering,priority/p0"

create_issue "[M5.2] 库存不足验证" \
  "预占失败时取消订单，已支付则退款" \
  "M5: 异常与一致性" "type/feature,module/inventory,priority/p0"

create_issue "[M5.3] 重复支付回调幂等验证" \
  "同一 PaymentId 重复回调不重复扣款" \
  "M5: 异常与一致性" "type/feature,module/payment,priority/p0"

create_issue "[M5.4] 并发下单不超卖验证" \
  "多线程并发下单同一 SKU，验证库存正确" \
  "M5: 异常与一致性" "type/feature,module/inventory,priority/p0"

create_issue "[M5.5] 消息重试与死信验证" \
  "消费失败后重试，超过次数进死信队列" \
  "M5: 异常与一致性" "type/feature,module/shared,priority/p1"

# ------------------------------------------------------------
# M6: 辅助模块
# ------------------------------------------------------------
echo ""
echo "--- M6: 辅助模块 ---"

# Cart
create_issue "[M6.1] Cart 聚合根" \
  "含 UserId、StoreId、Items 集合，存 Redis" \
  "M6: 辅助模块" "layer/domain,module/cart,priority/p1"

create_issue "[M6.2] CartItem 值对象" \
  "含 ProductId、SkuId、Quantity" \
  "M6: 辅助模块" "layer/domain,module/cart,priority/p1"

create_issue "[M6.3] 加购 / 改数量 / 删除 / 结算用例" \
  "Features/AddItem、UpdateQuantity、RemoveItem、Checkout" \
  "M6: 辅助模块" "layer/application,module/cart,priority/p1"

create_issue "[M6.4] Redis Cart 存储实现" \
  "ICartRepository 的 Redis 实现" \
  "M6: 辅助模块" "layer/infrastructure,module/cart,priority/p1"

create_issue "[M6.5] CartModule 注册 + 购物车端点" \
  "AddCartInfrastructure + POST /api/cart/items、PUT、DELETE、POST /checkout" \
  "M6: 辅助模块" "layer/api,module/cart,priority/p1"

# Notification
create_issue "[M6.6] Notification 聚合根 + 领域事件" \
  "含 UserId、Channel、Template、Status" \
  "M6: 辅助模块" "layer/domain,module/notification,priority/p2"

create_issue "[M6.7] 消费 OrderPlaced / OrderConfirmed / DeliveryCompleted" \
  "收到事件后创建 Notification 并发通知" \
  "M6: 辅助模块" "layer/application,module/notification,priority/p2"

create_issue "[M6.8] 模拟短信/推送 + NotificationModule 注册" \
  "开发用，日志输出即可" \
  "M6: 辅助模块" "layer/infrastructure,module/notification,priority/p2"

# Audit
create_issue "[M6.9] AuditLog 聚合根 + 领域事件" \
  "含 Actor、Action、Target、Timestamp" \
  "M6: 辅助模块" "layer/domain,module/audit,priority/p1"

create_issue "[M6.10] 消费所有关键事件写 ES" \
  "订阅 Order/Inventory/Payment/Delivery 关键事件" \
  "M6: 辅助模块" "layer/application,module/audit,priority/p1"

create_issue "[M6.11] ES 审计索引 + AuditModule 注册" \
  "audit-logs 索引，AddAuditInfrastructure" \
  "M6: 辅助模块" "layer/infrastructure,module/audit,priority/p1"

create_issue "[M6.12] 运营查询端点" \
  "GET /api/audit/logs，支持按 Actor / Action / 时间范围过滤" \
  "M6: 辅助模块" "layer/api,module/audit,priority/p1"

# Identity
create_issue "[M6.13] ASP.NET Core Identity 集成" \
  "ApplicationUser 继承 IdentityUser，共享 AspNetUsers 表" \
  "M6: 辅助模块" "layer/infrastructure,module/identity,priority/p0"

create_issue "[M6.14] User 聚合根 + UserRole 值对象" \
  "Consumer / Merchant / Rider / Operator 四种角色" \
  "M6: 辅助模块" "layer/domain,module/identity,priority/p0"

create_issue "[M6.15] 注册 / 登录用例" \
  "Features/Register、Login，签发 JWT" \
  "M6: 辅助模块" "layer/application,module/identity,priority/p0"

create_issue "[M6.16] 角色授权策略 + IdentityModule 注册" \
  "RequireConsumer / RequireMerchant / RequireRider / RequireOperator" \
  "M6: 辅助模块" "layer/api,module/identity,priority/p0"

# Search
create_issue "[M6.17] 独立搜索 API" \
  "GET /api/search/products，从 Catalog 拆出查询" \
  "M6: 辅助模块" "layer/api,module/search,priority/p1"

create_issue "[M6.18] SearchDocument 模型 + 索引重建工具" \
  "ES 索引结构；从 Catalog PostgreSQL 全量重建" \
  "M6: 辅助模块" "layer/infrastructure,module/search,priority/p1"

create_issue "[M6.19] SearchModule 注册" \
  "AddSearchInfrastructure + MapSearchEndpoints" \
  "M6: 辅助模块" "layer/infrastructure,module/search,priority/p1"

# ------------------------------------------------------------
# M7: 生产就绪
# ------------------------------------------------------------
echo ""
echo "--- M7: 生产就绪 ---"

create_issue "[M7.1] Dockerfile.Api" \
  "多阶段构建，镜像 < 200MB，非 root 用户" \
  "M7: 生产就绪" "type/chore,priority/p0"

create_issue "[M7.2] Dockerfile.Worker + .dockerignore" \
  "多阶段构建，排除 bin/obj/.git" \
  "M7: 生产就绪" "type/chore,priority/p0"

create_issue "[M7.3] K8s 基础设施 YAML" \
  "Namespace + PostgreSQL + Redis + RabbitMQ + ES + Kibana + EDOT Collector" \
  "M7: 生产就绪" "type/chore,priority/p0"

create_issue "[M7.4] K8s 应用 YAML" \
  "Api Deployment + Service + HPA；Worker Deployment + HPA" \
  "M7: 生产就绪" "type/chore,priority/p0"

create_issue "[M7.5] ConfigMap / Secret / Ingress" \
  "分环境配置；Nginx Ingress 路由 /api、/kibana、/rabbitmq" \
  "M7: 生产就绪" "type/chore,priority/p0"

create_issue "[M7.6] GitHub Actions：build + test" \
  "PR 触发，dotnet build + dotnet test" \
  "M7: 生产就绪" "type/chore,priority/p0"

create_issue "[M7.7] GitHub Actions：镜像构建 + 推送" \
  "main 分支合并后构建镜像推送到 registry" \
  "M7: 生产就绪" "type/chore,priority/p0"

create_issue "[M7.8] GitHub Actions：K8s 滚动更新" \
  "触发 kubectl set image 或 ArgoCD 同步" \
  "M7: 生产就绪" "type/chore,priority/p1"

create_issue "[M7.9] Testcontainers 集成测试基础设施" \
  "PostgreSQL + Redis + RabbitMQ + ES 一键启动" \
  "M7: 生产就绪" "type/chore,priority/p0"

create_issue "[M7.10] 持久化 + 消息集成测试" \
  "DbContext 映射；Outbox 投递、Inbox 幂等、重试、死信" \
  "M7: 生产就绪" "type/chore,priority/p0"

create_issue "[M7.11] API 集成测试 + 架构测试" \
  "WebApplicationFactory；NetArchTest 强制模块边界" \
  "M7: 生产就绪" "type/chore,priority/p0"

create_issue "[M7.12] 关键用例加 ActivitySource" \
  "PlaceOrder、ReserveInventory、ProcessPaymentCallback 等" \
  "M7: 生产就绪" "type/chore,priority/p1"

create_issue "[M7.13] 关键指标加 Counter / Histogram" \
  "orders.placed、orders.duration、inventory.conflicts 等" \
  "M7: 生产就绪" "type/chore,priority/p1"

create_issue "[M7.14] Kibana APM 视图配置" \
  "Traces / Logs / Metrics 三个视图" \
  "M7: 生产就绪" "type/chore,priority/p1"

# ------------------------------------------------------------
# M8: 稳定性验证
# ------------------------------------------------------------
echo ""
echo "--- M8: 稳定性验证 ---"

create_issue "[M8.1] k6 压测脚本" \
  "下单接口压测，含负载阶梯" \
  "M8: 稳定性验证" "type/chore,priority/p1"

create_issue "[M8.2] 500 并发无超卖验证" \
  "同一 SKU 高并发下单，库存最终一致" \
  "M8: 稳定性验证" "type/chore,priority/p1"

create_issue "[M8.3] RabbitMQ 宕机演练" \
  "模拟宕机，验证消息不丢，恢复后重投" \
  "M8: 稳定性验证" "type/chore,priority/p1"

create_issue "[M8.4] PostgreSQL / Redis 宕机演练" \
  "验证服务降级，恢复后自愈" \
  "M8: 稳定性验证" "type/chore,priority/p1"

create_issue "[M8.5] 服务重启 + Saga 状态恢复演练" \
  "重启后未完成流程继续执行" \
  "M8: 稳定性验证" "type/chore,priority/p1"

create_issue "[M8.6] 幂等 + 死信验证" \
  "重复消息不重复处理；失败消息可重放" \
  "M8: 稳定性验证" "type/chore,priority/p1"

create_issue "[M8.7] 压测 + 故障演练报告" \
  "QPS / P95 / P99 / 恢复时间 / 改进项" \
  "M8: 稳定性验证" "type/docs,priority/p2"

# ============================================================
# 6. 完成
# ============================================================
echo ""
echo "============================================================"
echo "✅ GitHub Projects 配置完成"
echo "============================================================"
echo ""
echo "Project：https://github.com/users/$OWNER/projects/$PROJECT_NUMBER"
echo ""

TOTAL_ISSUES=$(gh issue list --repo "$REPO" --limit 500 --json number --jq 'length' 2>/dev/null || echo "?")
echo "当前 Issue 总数：$TOTAL_ISSUES"
echo ""

echo "本次运行统计："
echo "  字段   ✅ $FIELD_SUCCESS  ⏭️  $FIELD_SKIPPED  ❌ $FIELD_FAILED"
echo "  标签   ✅ $LABEL_SUCCESS  ⏭️  $LABEL_SKIPPED  ❌ $LABEL_FAILED"
echo "  里程碑 ✅ $MS_SUCCESS     ⏭️  $MS_SKIPPED     ❌ $MS_FAILED"
echo "  Issue  ✅ $ISSUE_SUCCESS  ⏭️  $ISSUE_SKIPPED  ❌ $ISSUE_FAILED"
echo ""

if [[ $ISSUE_FAILED -gt 0 || $FIELD_FAILED -gt 0 || $LABEL_FAILED -gt 0 || $MS_FAILED -gt 0 ]]; then
  echo "⚠️  有失败项，请检查上方错误信息"
  echo ""
fi

echo "下一步（手动操作）："
echo ""
echo "  1. 配置 Status 字段选项（Web UI）："
echo "     https://github.com/users/$OWNER/projects/$PROJECT_NUMBER/settings/fields"
echo "     - 编辑 Status，添加：In Review / Blocked / Cancelled"
echo "     - 排序：Todo → In Progress → In Review → Blocked → Done → Cancelled"
echo ""
echo "  2. 配置视图（Web UI）："
echo "     https://github.com/users/$OWNER/projects/$PROJECT_NUMBER"
echo "     - Board  : Layout=Board,   Column by=Status,    Sort=Priority"
echo "     - Table  : Layout=Table,   Group by=Milestone,  Sort=Priority"
echo "     - Roadmap: Layout=Roadmap, Date field=Milestone"
echo "     - My Work: Layout=Table,   Filter=assignee:@me -status:Done"
echo ""
echo "  3. 启用 Workflows（Web UI）："
echo "     项目页面 → ... → Workflows"
echo "     - Item added to project → Set Status = Todo"
echo "     - Item closed → Set Status = Done"
echo "     - Auto-close issue"
echo "     - Auto-add sub-issues"
echo ""
echo "  4. 关联 Project 到仓库（可选）："
echo "     https://github.com/$REPO/projects → Link a project"
echo ""