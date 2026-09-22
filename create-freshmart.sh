#!/usr/bin/env bash
# create-freshmart.sh
# 严格分层：每模块 4 个 csproj（Domain / Application / Infrastructure / Api）
# 模块以模块名聚合为文件夹；宿主平铺在 src/ 下
# 幂等：可反复执行，已存在的跳过

set -euo pipefail

SOLUTION_NAME="FreshMart"
SOLUTION_FILE="${SOLUTION_NAME}.slnx"

# ============================================================
# 辅助函数
# ============================================================

sed_inplace() {
  if [[ "$(uname)" == "Darwin" ]]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

ensure_dir() {
  [[ -d "$1" ]] || mkdir -p "$1"
}

write_if_missing() {
  local file="$1"
  if [[ -f "$file" ]]; then
    echo "  ⏭️  已存在：$file"
    return 0
  fi
  cat > "$file"
  echo "  ✅ 创建：$file"
}

create_classlib_if_missing() {
  local name="$1"
  local path="$2"
  local proj="$path/$name.csproj"
  if [[ -f "$proj" ]]; then
    echo "  ⏭️  已存在：$name"
    return 0
  fi
  dotnet new classlib -n "$name" -o "$path" -f net10.0 >/dev/null
  rm -f "$path/Class1.cs"
  echo "  ✅ 创建：$name"
}

create_webapi_if_missing() {
  local name="$1"
  local path="$2"
  local proj="$path/$name.csproj"
  if [[ -f "$proj" ]]; then
    echo "  ⏭️  已存在：$name"
    return 0
  fi
  dotnet new webapi -n "$name" -o "$path" -f net10.0 >/dev/null
  echo "  ✅ 创建：$name"
}

create_worker_if_missing() {
  local name="$1"
  local path="$2"
  local proj="$path/$name.csproj"
  if [[ -f "$proj" ]]; then
    echo "  ⏭️  已存在：$name"
    return 0
  fi
  dotnet new worker -n "$name" -o "$path" -f net10.0 >/dev/null
  echo "  ✅ 创建：$name"
}

create_xunit_if_missing() {
  local name="$1"
  local path="$2"
  local proj="$path/$name.csproj"
  if [[ -f "$proj" ]]; then
    echo "  ⏭️  已存在：$name"
    return 0
  fi
  dotnet new xunit -n "$name" -o "$path" -f net10.0 >/dev/null
  echo "  ✅ 创建：$name"
}

# 给类库添加 ASP.NET Core FrameworkReference（幂等）
add_aspnetcore_framework_reference() {
  local csproj="$1"
  [[ -f "$csproj" ]] || return 0
  if grep -q "Microsoft.AspNetCore.App" "$csproj"; then
    return 0
  fi
  local tmp
  tmp=$(mktemp)
  awk '
    /<\/Project>/ {
      print "  <ItemGroup>"
      print "    <FrameworkReference Include=\"Microsoft.AspNetCore.App\" />"
      print "  </ItemGroup>"
    }
    { print }
  ' "$csproj" > "$tmp"
  mv "$tmp" "$csproj"
}

# ============================================================
# 0. 全局配置文件
# ============================================================
echo "=== 0. 全局配置文件 ==="

write_if_missing Directory.Build.props <<'EOF'
<Project>
  <PropertyGroup>
    <LangVersion>latest</LangVersion>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
  </PropertyGroup>
</Project>
EOF

write_if_missing Directory.Packages.props <<'EOF'
<Project>
  <PropertyGroup>
    <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
    <CentralPackageTransitivePinningEnabled>true</CentralPackageTransitivePinningEnabled>
  </PropertyGroup>

  <ItemGroup Label="Persistence">
    <PackageVersion Include="Microsoft.EntityFrameworkCore" Version="10.0.10" />
    <PackageVersion Include="Microsoft.EntityFrameworkCore.Design" Version="10.0.10" />
    <PackageVersion Include="Microsoft.EntityFrameworkCore.Relational" Version="10.0.10" />
    <PackageVersion Include="Npgsql.EntityFrameworkCore.PostgreSQL" Version="10.0.3" />
  </ItemGroup>

  <ItemGroup Label="Messaging">
    <PackageVersion Include="WolverineFx" Version="5.41.0" />
    <PackageVersion Include="WolverineFx.RabbitMQ" Version="5.41.0" />
    <PackageVersion Include="RabbitMQ.Client" Version="7.2.2" />
  </ItemGroup>

  <ItemGroup Label="Caching">
    <PackageVersion Include="StackExchange.Redis" Version="3.1.31" />
    <PackageVersion Include="Microsoft.Extensions.Caching.StackExchangeRedis" Version="10.0.12" />
  </ItemGroup>

  <ItemGroup Label="Search">
    <PackageVersion Include="Elastic.Clients.Elasticsearch" Version="9.5.1" />
  </ItemGroup>

  <ItemGroup Label="Mediator">
    <PackageVersion Include="Mediator.Abstractions" Version="4.0.1" />
    <PackageVersion Include="Mediator.SourceGenerator" Version="4.0.1" />
  </ItemGroup>

  <ItemGroup Label="AOP">
    <PackageVersion Include="Metalama.Framework" Version="2026.0.17" />
  </ItemGroup>

  <ItemGroup Label="Identity">
    <PackageVersion Include="Microsoft.AspNetCore.Identity.EntityFrameworkCore" Version="10.0.12" />
    <PackageVersion Include="Microsoft.AspNetCore.Authentication.JwtBearer" Version="10.0.12" />
  </ItemGroup>

  <ItemGroup Label="Observability">
    <PackageVersion Include="OpenTelemetry.Extensions.Hosting" Version="1.16.0" />
    <PackageVersion Include="OpenTelemetry.Exporter.OpenTelemetryProtocol" Version="1.16.0" />
    <PackageVersion Include="OpenTelemetry.Instrumentation.AspNetCore" Version="1.15.2" />
    <PackageVersion Include="OpenTelemetry.Instrumentation.Http" Version="1.15.2" />
    <PackageVersion Include="OpenTelemetry.Instrumentation.EntityFrameworkCore" Version="1.15.2" />
    <PackageVersion Include="OpenTelemetry.Instrumentation.Runtime" Version="1.15.2" />
    <PackageVersion Include="WolverineFx.OpenTelemetry" Version="5.41.0" />
  </ItemGroup>

  <ItemGroup Label="Hosting">
    <PackageVersion Include="Microsoft.Extensions.Hosting" Version="10.0.12" />
  </ItemGroup>

  <ItemGroup Label="AspNetCore">
    <PackageVersion Include="Microsoft.AspNetCore.OpenApi" Version="10.0.12" />
  </ItemGroup>

  <ItemGroup Label="Testing">
    <PackageVersion Include="Microsoft.NET.Test.Sdk" Version="17.12.0" />
    <PackageVersion Include="xunit.v3" Version="4.0.0" />
    <PackageVersion Include="xunit.runner.visualstudio" Version="3.1.0" />
    <PackageVersion Include="coverlet.collector" Version="6.0.2" />
    <PackageVersion Include="FluentAssertions" Version="7.1.0" />
    <PackageVersion Include="Testcontainers.PostgreSql" Version="4.14.0" />
    <PackageVersion Include="Testcontainers.Redis" Version="4.14.0" />
    <PackageVersion Include="Testcontainers.RabbitMq" Version="4.14.0" />
    <PackageVersion Include="Testcontainers.Elasticsearch" Version="4.14.0" />
  </ItemGroup>

  <ItemGroup Label="Architecture">
    <PackageVersion Include="NetArchTest.Rules" Version="1.3.2" />
  </ItemGroup>
</Project>
EOF

write_if_missing .gitignore <<'EOF'
# ============================================================
# .NET / Visual Studio / Rider
# ============================================================
[Bb]in/
[Oo]bj/
[Ll]og/
[Ll]ogs/
[Oo]ut/
[Pp]ublish/
[Pp]ackages/
*.user
*.userosscache
*.sln.docstates
*.suo
*.userprefs
*.rsuser

.vs/
*.vsidx
*.vscode/
!.vscode/launch.json
!.vscode/tasks.json
!.vscode/extensions.json

.idea/
*.sln.iml

.history/

# ============================================================
# 构建产物
# ============================================================
[Dd]ebug/
[Rr]elease/
x64/
x86/
[Ww][Ii][Nn]32/
[Aa][Rr][Mm]/
[Aa][Rr][Mm]64/
build/
bld/
artifacts/
TestResults/
*.trx
*.coverage
*.coverlet.json
coverage*.json
coverage*.xml
coverage*.info

# NuGet
*.nupkg
*.snupkg
**/[Pp]ackages/*
!**/[Pp]ackages/build/
project.lock.json
project.fragment.lock.json
artifacts/

# ============================================================
# 用户/本地配置
# ============================================================
appsettings.Development.local.json
appsettings.Local.json
*.local.json
launchSettings.json

*.pfx
*.p12
*.key
*.pem
!deploy/nginx/certs/.gitkeep

secrets.json
*.secrets.json

# ============================================================
# Podman / Docker
# ============================================================
.dockerignore
docker-compose.override.yml
docker-compose.*.local.yml
*.pid
*.seed
*.pid.lock

podman-volumes/

# ============================================================
# Kubernetes
# ============================================================
*.kubeconfig
kubeconfig
.kube/
deploy/k8s/**/secret*.yaml
!deploy/k8s/**/secret.example.yaml

# ============================================================
# 数据库
# ============================================================
*.db
*.db-shm
*.db-wal
*.sqlite
*.sqlite3
*.mdf
*.ldf
*.ndf

postgres-data/
pgdata/

# ============================================================
# Redis / RabbitMQ / Elasticsearch 本地数据
# ============================================================
redis-data/
rabbitmq-data/
elasticsearch-data/
es-data/

# ============================================================
# 日志
# ============================================================
logs/
*.log
npm-debug.log*
yarn-debug.log*
yarn-error.log*

# ============================================================
# 环境变量
# ============================================================
.env
.env.local
.env.*.local
!.env.example

# ============================================================
# 操作系统
# ============================================================
.DS_Store
.DS_Store?
._*
.Spotlight-V100
.Trashes
ehthumbs.db
Thumbs.db
desktop.ini

# ============================================================
# 临时文件
# ============================================================
*.tmp
*.temp
*.bak
*.swp
*~
*.orig
*.rej

# ============================================================
# 工具
# ============================================================
*.metalama/
metalama-cache/
Metalama.Cache/

*.efcore.tmp

.dotnet/
tools/
EOF

write_if_missing .editorconfig <<'EOF'
# 顶层配置，告诉编辑器到此为止
root = true

[*]
charset = utf-8
end_of_line = lf
insert_final_newline = true
trim_trailing_whitespace = true
indent_style = space
indent_size = 4
max_line_length = 120

[*.cs]
indent_size = 4

dotnet_naming_rule.private_fields_should_be_underscore_camel_case.severity = warning
dotnet_naming_rule.private_fields_should_be_underscore_camel_case.symbols = private_fields
dotnet_naming_rule.private_fields_should_be_underscore_camel_case.style = underscore_camel_case

dotnet_naming_symbols.private_fields.applicable_kinds = field
dotnet_naming_symbols.private_fields.applicable_accessibilities = private
dotnet_naming_symbols.private_fields.required_modifiers = readonly

dotnet_naming_style.underscore_camel_case.required_prefix = _
dotnet_naming_style.underscore_camel_case.capitalization = camel_case

dotnet_naming_rule.private_non_readonly_fields_should_be_underscore_camel_case.severity = warning
dotnet_naming_rule.private_non_readonly_fields_should_be_underscore_camel_case.symbols = private_non_readonly_fields
dotnet_naming_rule.private_non_readonly_fields_should_be_underscore_camel_case.style = underscore_camel_case

dotnet_naming_symbols.private_non_readonly_fields.applicable_kinds = field
dotnet_naming_symbols.private_non_readonly_fields.applicable_accessibilities = private

dotnet_naming_rule.constants_should_be_pascal_case.severity = warning
dotnet_naming_rule.constants_should_be_pascal_case.symbols = constants
dotnet_naming_rule.constants_should_be_pascal_case.style = pascal_case

dotnet_naming_symbols.constants.applicable_kinds = field
dotnet_naming_symbols.constants.required_modifiers = const

dotnet_naming_style.pascal_case.capitalization = pascal_case

dotnet_naming_rule.interfaces_should_be_prefixed_with_i.severity = warning
dotnet_naming_rule.interfaces_should_be_prefixed_with_i.symbols = interfaces
dotnet_naming_rule.interfaces_should_be_prefixed_with_i.style = interface_style

dotnet_naming_symbols.interfaces.applicable_kinds = interface

dotnet_naming_style.interface_style.required_prefix = I
dotnet_naming_style.interface_style.capitalization = pascal_case

dotnet_naming_rule.type_parameters_should_be_prefixed_with_t.severity = warning
dotnet_naming_rule.type_parameters_should_be_prefixed_with_t.symbols = type_parameters
dotnet_naming_rule.type_parameters_should_be_prefixed_with_t.style = type_parameter_style

dotnet_naming_symbols.type_parameters.applicable_kinds = type_parameter

dotnet_naming_style.type_parameter_style.required_prefix = T
dotnet_naming_style.type_parameter_style.capitalization = pascal_case

dotnet_style_qualification_for_field = false:suggestion
dotnet_style_qualification_for_property = false:suggestion
dotnet_style_qualification_for_method = false:suggestion
dotnet_style_qualification_for_event = false:suggestion

dotnet_style_predefined_type_for_locals_parameters_members = true:suggestion
dotnet_style_predefined_type_for_member_access = true:suggestion

dotnet_style_require_accessibility_modifiers = for_non_interface_members:warning
csharp_preferred_modifier_order = public,private,protected,internal,static,extern,new,virtual,abstract,sealed,override,readonly,unsafe,volatile,async:suggestion

csharp_style_expression_bodied_methods = when_on_single_line:suggestion
csharp_style_expression_bodied_constructors = when_on_single_line:suggestion
csharp_style_expression_bodied_properties = true:suggestion
csharp_style_expression_bodied_indexers = true:suggestion
csharp_style_expression_bodied_accessors = true:suggestion

csharp_style_pattern_matching_over_is_with_cast_check = true:suggestion
csharp_style_pattern_matching_over_as_with_null_check = true:suggestion
csharp_style_prefer_switch_expression = true:suggestion

csharp_style_throw_expression = true:suggestion
csharp_style_conditional_delegate_call = true:suggestion
csharp_style_prefer_null_check_over_is_null = true:suggestion

csharp_style_var_for_built_in_types = false:suggestion
csharp_style_var_when_type_is_apparent = true:suggestion
csharp_style_var_elsewhere = false:suggestion

csharp_style_namespace_declarations = file_scoped:warning
csharp_style_prefer_primary_constructors = true:suggestion

dotnet_sort_system_directives_first = true
dotnet_separate_import_directive_groups = false
csharp_using_directive_placement = outside_namespace:warning
csharp_style_prefer_global_using_directive = true:suggestion

dotnet_diagnostic.IDE0005.severity = warning
dotnet_diagnostic.IDE0051.severity = warning

csharp_style_prefer_collection_expression = true:suggestion
csharp_style_prefer_extended_property_pattern = true:suggestion
csharp_style_implicit_object_creation_when_type_is_apparent = true:suggestion
csharp_style_prefer_index_operator = true:suggestion
csharp_style_prefer_range_operator = true:suggestion

dotnet_analyzer_diagnostic.category-Style.severity = warning
dotnet_analyzer_diagnostic.category-Performance.severity = warning
dotnet_analyzer_diagnostic.category-Security.severity = warning
dotnet_analyzer_diagnostic.category-Reliability.severity = warning

csharp_style_prefer_local_over_anonymous_function = true:suggestion
csharp_style_prefer_method_group_conversion = true:suggestion

dotnet_diagnostic.CA2007.severity = none

[*.{csproj,props,targets,proj}]
indent_size = 2

[*.{json,yml,yaml}]
indent_size = 2

[*.{xml,config}]
indent_size = 2

[*.md]
trim_trailing_whitespace = false

[*.{sh,bash}]
indent_size = 2

[Dockerfile*]
indent_size = 4
EOF

write_if_missing .gitattributes <<'EOF'
* text=auto eol=lf

*.cs        text eol=lf
*.csproj    text eol=lf
*.props     text eol=lf
*.targets   text eol=lf
*.sln       text eol=lf
*.slnx      text eol=lf
*.json      text eol=lf
*.xml       text eol=lf
*.config    text eol=lf
*.yml       text eol=lf
*.yaml      text eol=lf
*.md        text eol=lf
*.http      text eol=lf
*.sh        text eol=lf

*.bat       text eol=crlf
*.cmd       text eol=crlf
*.ps1       text eol=crlf

*.png       binary
*.jpg       binary
*.jpeg      binary
*.gif       binary
*.ico       binary
*.pdf       binary
*.zip       binary
*.gz        binary
*.tar       binary
*.dll       binary
*.exe       binary
*.so        binary
*.dylib     binary
*.pfx       binary
*.p12       binary
*.snk       binary

packages.lock.json text eol=lf

Dockerfile*  text eol=lf
EOF

# ============================================================
# 1. 解决方案
# ============================================================
echo ""
echo "=== 1. 解决方案 ==="

if [[ -f "$SOLUTION_FILE" ]]; then
  echo "  ⏭️  已存在：$SOLUTION_FILE"
else
  dotnet new sln -n "$SOLUTION_NAME" >/dev/null
  if [[ ! -f "$SOLUTION_FILE" ]]; then
    echo "  ❌ 解决方案创建失败：$SOLUTION_FILE" >&2
    exit 1
  fi
  echo "  ✅ 创建：$SOLUTION_FILE"
fi

# ============================================================
# 2. BuildingBlocks
# ============================================================
echo ""
echo "=== 2. BuildingBlocks ==="

BUILDING_BLOCKS=(
  "FreshMart.Shared.Core"
  "FreshMart.Shared.Persistence"
  "FreshMart.Shared.Web"
  "FreshMart.Shared.Validation"
  "FreshMart.Shared.Messaging"
  "FreshMart.Shared.Contracts"
)

for bb in "${BUILDING_BLOCKS[@]}"; do
  create_classlib_if_missing "$bb" "src/BuildingBlocks/$bb"
done

# ============================================================
# 3. Modules（每模块 4 个 csproj，按模块名聚合）
# ============================================================
echo ""
echo "=== 3. Modules ==="

MODULES=(
  "Catalog" "Inventory" "Cart" "Ordering"
  "Payment" "Delivery" "Notification" "Search"
  "Audit" "Identity"
)

for module in "${MODULES[@]}"; do
  root="src/$module"

  # ---- Domain ----
  domain="$root/FreshMart.$module.Domain"
  create_classlib_if_missing "FreshMart.$module.Domain" "$domain"
  ensure_dir "$domain/Events"
  ensure_dir "$domain/ValueObjects"
  ensure_dir "$domain/Services"

  # ---- Application ----
  app="$root/FreshMart.$module.Application"
  create_classlib_if_missing "FreshMart.$module.Application" "$app"
  ensure_dir "$app/Features"
  ensure_dir "$app/Abstractions"
  ensure_dir "$app/Sagas"

  # ---- Infrastructure ----
  infra="$root/FreshMart.$module.Infrastructure"
  create_classlib_if_missing "FreshMart.$module.Infrastructure" "$infra"
  ensure_dir "$infra/Persistence/Configurations"
  ensure_dir "$infra/Persistence/Repositories"
  ensure_dir "$infra/Messaging"
  ensure_dir "$infra/Clients"

  # ---- Api（类库 + FrameworkReference） ----
  api="$root/FreshMart.$module.Api"
  create_classlib_if_missing "FreshMart.$module.Api" "$api"
  ensure_dir "$api/Features"
  add_aspnetcore_framework_reference "$api/FreshMart.$module.Api.csproj"
done

# ============================================================
# 4. Hosts（平铺在 src/ 下）
# ============================================================
echo ""
echo "=== 4. Hosts ==="

create_webapi_if_missing "$SOLUTION_NAME.Api"    "src/$SOLUTION_NAME.Api"
create_worker_if_missing "$SOLUTION_NAME.Worker" "src/$SOLUTION_NAME.Worker"

# ============================================================
# 5. Tests
# ============================================================
echo ""
echo "=== 5. Tests ==="

TEST_PROJECTS=(
  "FreshMart.Catalog.Tests"
  "FreshMart.Ordering.Tests"
  "FreshMart.IntegrationTests"
  "FreshMart.ArchitectureTests"
)

for test in "${TEST_PROJECTS[@]}"; do
  create_xunit_if_missing "$test" "tests/$test"
done

# ============================================================
# 6. 清理 csproj 的 Version 属性（CPM 要求）
# ============================================================
echo ""
echo "=== 6. 清理 csproj 的 Version 属性（CPM） ==="

changed=0
while IFS= read -r csproj; do
  if grep -qE ' +Version="[^"]*"' "$csproj"; then
    sed_inplace -E 's/ +Version="[^"]*"//g' "$csproj"
    changed=$((changed + 1))
  fi
done < <(find src tests -name "*.csproj")

if [[ $changed -gt 0 ]]; then
  echo "  ✅ 清理了 $changed 个 csproj"
else
  echo "  ⏭️  无需清理"
fi

# ============================================================
# 7. 添加所有项目到解决方案
# ============================================================
echo ""
echo "=== 7. 添加项目到解决方案 ==="

mapfile -t ALL_CSPROJ < <(find . -name "*.csproj" -not -path "*/obj/*" -not -path "*/bin/*")

added=0
for proj in "${ALL_CSPROJ[@]}"; do
  output=$(dotnet sln "$SOLUTION_FILE" add "$proj" 2>&1 || true)
  if [[ "$output" != *"already"* ]]; then
    added=$((added + 1))
  fi
done
echo "  ✅ 新增 $added 个项目（共扫描 ${#ALL_CSPROJ[@]} 个）"

# ============================================================
# 8. 配置项目引用（严格分层）
# ============================================================
echo ""
echo "=== 8. 配置项目引用 ==="

# ---- BuildingBlocks 内部 ----
for sp in FreshMart.Shared.Persistence FreshMart.Shared.Web FreshMart.Shared.Validation FreshMart.Shared.Messaging FreshMart.Shared.Contracts; do
  dotnet add "src/BuildingBlocks/$sp/$sp.csproj" \
    reference "src/BuildingBlocks/FreshMart.Shared.Core/FreshMart.Shared.Core.csproj" >/dev/null
done
echo "  ✅ BuildingBlocks 内部引用"

# ---- 模块各层引用 ----
for module in "${MODULES[@]}"; do
  root="src/$module"
  domain="$root/FreshMart.$module.Domain/FreshMart.$module.Domain.csproj"
  app="$root/FreshMart.$module.Application/FreshMart.$module.Application.csproj"
  infra="$root/FreshMart.$module.Infrastructure/FreshMart.$module.Infrastructure.csproj"
  api="$root/FreshMart.$module.Api/FreshMart.$module.Api.csproj"

  # Domain → Shared.Core
  dotnet add "$domain" \
    reference "src/BuildingBlocks/FreshMart.Shared.Core/FreshMart.Shared.Core.csproj" >/dev/null

  # Application → Domain + Shared.Core + Shared.Validation
  dotnet add "$app" reference "$domain" >/dev/null
  dotnet add "$app" \
    reference "src/BuildingBlocks/FreshMart.Shared.Core/FreshMart.Shared.Core.csproj" >/dev/null
  dotnet add "$app" \
    reference "src/BuildingBlocks/FreshMart.Shared.Validation/FreshMart.Shared.Validation.csproj" >/dev/null

  # Infrastructure → Application + Domain + Shared.Persistence + Shared.Messaging + Shared.Contracts
  dotnet add "$infra" reference "$app" >/dev/null
  dotnet add "$infra" reference "$domain" >/dev/null
  dotnet add "$infra" \
    reference "src/BuildingBlocks/FreshMart.Shared.Persistence/FreshMart.Shared.Persistence.csproj" >/dev/null
  dotnet add "$infra" \
    reference "src/BuildingBlocks/FreshMart.Shared.Messaging/FreshMart.Shared.Messaging.csproj" >/dev/null
  dotnet add "$infra" \
    reference "src/BuildingBlocks/FreshMart.Shared.Contracts/FreshMart.Shared.Contracts.csproj" >/dev/null

  # Api → Application + Domain + Shared.Web
  dotnet add "$api" reference "$app" >/dev/null
  dotnet add "$api" reference "$domain" >/dev/null
  dotnet add "$api" \
    reference "src/BuildingBlocks/FreshMart.Shared.Web/FreshMart.Shared.Web.csproj" >/dev/null
done
echo "  ✅ ${#MODULES[@]} 个模块 × 4 层引用"

# ---- Hosts ----
ALL_MODULE_API_PROJECTS=()
ALL_MODULE_INFRA_PROJECTS=()
for m in "${MODULES[@]}"; do
  ALL_MODULE_API_PROJECTS+=("src/$m/FreshMart.$m.Api/FreshMart.$m.Api.csproj")
  ALL_MODULE_INFRA_PROJECTS+=("src/$m/FreshMart.$m.Infrastructure/FreshMart.$m.Infrastructure.csproj")
done

# Api 宿主：Shared.Core + Shared.Web + 所有模块 Api + 所有模块 Infrastructure（DI 注册用）
dotnet add "src/$SOLUTION_NAME.Api/$SOLUTION_NAME.Api.csproj" \
  reference "src/BuildingBlocks/FreshMart.Shared.Core/FreshMart.Shared.Core.csproj" >/dev/null
dotnet add "src/$SOLUTION_NAME.Api/$SOLUTION_NAME.Api.csproj" \
  reference "src/BuildingBlocks/FreshMart.Shared.Web/FreshMart.Shared.Web.csproj" >/dev/null
dotnet add "src/$SOLUTION_NAME.Api/$SOLUTION_NAME.Api.csproj" \
  reference "${ALL_MODULE_API_PROJECTS[@]}" >/dev/null
dotnet add "src/$SOLUTION_NAME.Api/$SOLUTION_NAME.Api.csproj" \
  reference "${ALL_MODULE_INFRA_PROJECTS[@]}" >/dev/null

# Worker 宿主：Shared.Core + Shared.Messaging + 所有模块 Infrastructure
dotnet add "src/$SOLUTION_NAME.Worker/$SOLUTION_NAME.Worker.csproj" \
  reference "src/BuildingBlocks/FreshMart.Shared.Core/FreshMart.Shared.Core.csproj" >/dev/null
dotnet add "src/$SOLUTION_NAME.Worker/$SOLUTION_NAME.Worker.csproj" \
  reference "src/BuildingBlocks/FreshMart.Shared.Messaging/FreshMart.Shared.Messaging.csproj" >/dev/null
dotnet add "src/$SOLUTION_NAME.Worker/$SOLUTION_NAME.Worker.csproj" \
  reference "${ALL_MODULE_INFRA_PROJECTS[@]}" >/dev/null

echo "  ✅ Hosts 引用"

# ============================================================
# 9. 验证构建
# ============================================================
echo ""
echo "=== 9. 验证构建 ==="
if dotnet build -v quiet; then
  echo "  ✅ 构建成功"
else
  echo "  ⚠️  构建失败" >&2
  exit 1
fi

# ============================================================
# 10. 完成
# ============================================================
echo ""
echo "=== ✅ 完成 ==="
echo "项目数："
echo "  - BuildingBlocks        : ${#BUILDING_BLOCKS[@]}"
echo "  - Modules × 4 层         : $(( ${#MODULES[@]} * 4 ))"
echo "  - Hosts                 : 2"
echo "  - Tests                 : ${#TEST_PROJECTS[@]}"
echo "  - 合计                  : $(( ${#BUILDING_BLOCKS[@]} + ${#MODULES[@]} * 4 + 2 + ${#TEST_PROJECTS[@]} ))"
echo ""
echo "常用命令："
echo "  dotnet build                              # 构建"
echo "  dotnet sln $SOLUTION_FILE list             # 查看项目"
echo "  dotnet test                               # 运行测试"
echo "  dotnet run --project src/$SOLUTION_NAME.Api"