# Mooncedar — Checkpoint

MoonBit 实现的 Cedar 策略语言解析器、评估器与授权器。`jaredzhou/mooncedar@0.1.1`

## 参考

| 来源 | 地址 |
|------|------|
| Cedar 官方规范 | https://www.cedarpolicy.com |
| Rust 实现 (AWS) | https://github.com/cedar-policy/cedar |
| Go 实现 | https://github.com/cedar-policy/cedar-go |

## 项目结构

```
mooncedar/
├── moon.mod                    # 模块定义
├── moon.pkg                    # 根包导入 (evaluator, ast, parser, debug, json)
├── types.mbt                   # 顶层重导出: parse_policies, stringify, stringify_expr
├── authorizer.mbt              # 授权 API + 输出类型: evaluate / reauthorize / concretize / is_authorized
│                                #   PartialAuthorizationAnswer (satisfied + residuals + errors)
│                                #   substitute_unknowns — mapping 替换表达式 Unknown 节点
├── authorizer_wbtest.mbt       # 授权器白盒测试: is_authorized(6) + evaluate(3) + concretize(1) + reauthorize(10)
├── entity_store.mbt            # MapEntityStore + EntityStore impl + ToJson/FromJson + cedar_*_json + new_map_store
├── entity_store_wbtest.mbt     # MapEntityStore JSON 测试 (7 个) — inspect snapshot
├── example_wbtest.mbt          # 端到端示例测试 (3 个) — 从字符串解析 policy + entities
├── .claude/skills/using-mooncedar/SKILL.md  # 集成 skill
├── ast/
│   ├── moon.pkg                # 导入 (json, debug)
│   ├── types.mbt               # 纯 AST 类型 (EntityUID, EntityType, Pattern, Type, Value, PartialValue, Entity)
│   ├── expr.mbt                # 表达式 AST (Literal, VarKind, UnaryOp, BinaryOp, Expr, Unknown) + builder
│   ├── policy.mbt              # 策略 AST (Policy, ScopeConstraint, Condition, PolicyEffect) + builder
│   ├── validator.mbt           # 策略验证器 (ValidationError, validate_policy)
│   ├── builder_wbtest.mbt      # Builder 测试
│   └── validator_wbtest.mbt    # 验证器测试
├── evaluator/
│   ├── moon.pkg                # 导入 (ast, debug, json)
│   ├── types.mbt               # EntityStore(trait), EvalError, Dereference, EntityUIDEntry, Context, Request
│   ├── pattern_match.mbt       # wildcard_match — 双指针回溯
│   ├── scope_eval.mbt          # scope_match + is_descendant BFS
│   ├── operator.mbt            # eval_unary + eval_binary
│   ├── expr_eval.mbt           # eval_expr — 16 种 Expr 递归求值 + try_eval + get_attr_value + value_to_expr
│   ├── policy_eval.mbt         # eval_policy — scope + conditions + 残差合并
│   └── eval_wbtest.mbt         # 评估器白盒测试 (117 个) — CPE 语义, entity hierarchy, policy eval
└── parser/
    ├── moon.pkg                # 导入 (ast, debug)
    ├── lexer.mbt               # tokenize — 词法分析
    ├── expr_parser.mbt         # parse_expr — 递归下降
    ├── parser.mbt              # parse_policies — 策略解析
    ├── stringify.mbt           # AST → Cedar 源码
    ├── expr_wbtest.mbt         # 表达式解析测试
    ├── parser_wbtest.mbt       # 策略解析测试
    └── stringify_wbtest.mbt    # Stringify inspect 测试
```

**总代码量**: ~8000 行 | **测试**: 569 个 (569 通过)

## 已完成

### AST 类型系统 ✓
- [x] `Expr` — 完整 Cedar 表达式 AST (18 种节点)
- [x] `Unknown(String, Option[Type])` — 带可选类型标注
- [x] `PartialValue` — `Value(Value) | Residual(Expr)` 统一 partial eval 返回类型
- [x] `Policy` / `ScopeConstraint` / `ConditionKind` / `Condition` / `PolicyEffect`
- [x] 基础类型: EntityUID, EntityType, Name, Pattern, Type, Value, Entity

### Builder 模式 ✓
- [x] Expr 构造器 + 链式方法 (22 个)，命名统一 `expr_` 前缀: `expr_bool`, `expr_str`, `expr_euid`, `expr_principal`, `expr_resource`, `expr_unknown`, `expr_if`, `expr_not`, `expr_record` 等
- [x] Policy builder: `default()`, `permit`, `forbid`, scope 方法, `when_`, `unless`
- [x] 辅助函数: `entity_uid()`, `entity_type()`

### 解析器 ✓
- [x] 词法分析 (`tokenize`): 关键字(11), 运算符(11)
- [x] 表达式递归下降，Cedar 语法规范优先级
- [x] 策略解析: 多策略, 注解, effect, scope, conditions, InSet
- [x] 每策略解析后立即执行语义验证

### Stringify ✓
- [x] AST → Cedar 源码，优先级最小括号化 (9 级)
- [x] 公开 API: `stringify_expr`, `stringify`

### 策略验证器 ✓
- [x] `ValidationError` / `validate_policy` / `validate_policies`

### 评估器 ✓
- [x] `trait EntityStore` (pub(open) — 跨包可实现) — 可插拔实体存储
- [x] `EntityUIDEntry = Concrete | Unknown` / `Context = Concrete | Unknown | Partial` / `Request` — PARC + partial eval
- [x] `concrete_uid`, `unknown_uid`, `concrete_context`, `unknown_context`, `partial_context` — 便捷构造器
- [x] `wildcard_match` — 双指针回溯通配符匹配
- [x] `scope_match` + `is_descendant` — scope 匹配 + BFS 层次遍历
- [x] `eval_unary` (3 种) + `eval_binary` (12 种) — checked overflow
- [x] `eval_expr` — 18 种 Expr 递归求值，含 And/Or 短路 (匹配 Rust CPE 语义)
- [x] `get_attr_value` — 记录/实体属性查找，Context::Partial 可投影 Unknown
- [x] `value_to_expr` — Value 转 Expr，含 Record 展开
- [x] `eval_policy` — scope + when/unless 条件求值，Unknown PARC 生成残差
- [x] `try_eval` — 残差侧错误抑制

### 授权器 ✓
- [x] `evaluate` — 策略集求值 → `PartialAuthorizationAnswer`
- [x] `reauthorize` — 方法：用扩充 store + mapping 重新求值残差
- [x] `concretize` — 方法：提取二元 Allow/Deny
- [x] `is_authorized` — evaluate + concretize 便捷封装
- [x] `substitute_unknowns` — mapping 替换表达式 Unknown 节点
- [x] `Decision` / `DiagnosticReason` / `DiagnosticError` / `AuthorizationResult` — 输出类型

### Reauthorize 测试 (5 类 Unknown) ✓
- [x] **Cat 1: PARC unknown** — unknown principal 被 mapping / 不解析
- [x] **Cat 2: Context attr unknown** — 可投影字段映射 / 不可投影 context 级映射 / 不存在 key → error
- [x] **Cat 3: Policy expr unknown** — `expr_unknown("flag")` 被 mapping / 不解析
- [x] **Cat 4: Entity missing** — in 操作符解析 / 仍缺失 / forbid 解析 / satisfied 前传
- [x] ~~Cat 5: Entity attr unknown~~ — 已删除，Entity 回退为 `Map[String, Value]`

### JSON 序列化 ✓
- [x] `EntityUID` — 手动实现 `ToJson` / `FromJson`，`type_` ↔ `"type"` 字段映射
- [x] `Entity` / `Value` / `Name` / `EntityType` — `derive(ToJson, FromJson)`
- [x] `MapEntityStore` — 手动实现 `ToJson` / `FromJson`，纯数组格式
- [x] `cedar_entity_from_json` / `cedar_value_from_json` / `cedar_value_from_object` — Cedar JSON 解析器

### 已验证 ✓
- [x] `moon check`: 0 errors
- [x] `moon test`: 569/569 通过

### 待实现

1. **模板支持** — `Expr::Slot` 模板实例化
2. **扩展函数** — IP, decimal 等实际求值
3. **TPE** — schema + type checker 后，typed Unknown 短路优化

## 设计约定

- **命名**: `expr_*` 为表达式构造器 (如 `expr_bool`, `expr_principal`, `expr_unknown`); 方法为链式 `.eq()`, `.access()`, `.has_tag()` 等
- **Builder**: 方法定义在类型上 (无 wrapper)
- **包结构**: `ast/` (语言定义) → `evaluator/` (求值 trait) → 根 `authorizer.mbt` (授权 API) → 根 `entity_store.mbt` (实体存储)
- **求值**: `PartialValue` 统一返回; store-dependent 运算内联; `try/catch` 边界捕获
- **EntityStore**: `trait` 可插拔实现 (`pub(open)` generic `[S : EntityStore]`); 默认 `MapEntityStore` 在根包
- **策略迭代**: `evaluate` / `is_authorized` 接受 `Iter[Policy]`
- **测试字符串**: 用 `#|content|` 单行原始字符串
