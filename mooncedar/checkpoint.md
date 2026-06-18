# Mooncedar — Checkpoint

MoonBit 实现的 Cedar 策略语言解析器与 AST。`jaredzhou/mooncedar@0.1.0`

---

## 项目结构

```
mooncedar/
├── moon.mod                    # 模块定义
├── moon.pkg                    # 根包导入 (json)
├── types.mbt                   # 顶层重导出（占位）
├── ast/
│   ├── moon.pkg                # 导入 (json, debug)
│   ├── types.mbt               # 基础类型 (EntityUID, EntityType, Name, Pattern, Type, Value, Entity, Request, ...)
│   ├── expr.mbt                # 表达式 AST (Literal, BinaryOp, UnaryOp, VarKind, Expr) + builder (~30 个函数/方法)
│   ├── policy.mbt              # 策略类型 (Policy, ScopeConstraint, ConditionKind, Annotation, PolicyEffect) + builder (~20 个方法)
│   └── builder_wbtest.mbt      # Builder 白盒测试 (~43 个测试)
└── parser/
    ├── moon.pkg                # 导入 (ast, debug)
    ├── lexer.mbt               # 词法分析 (Token, TokenKind, Keyword, Operator)
    ├── expr_parser.mbt         # 表达式递归下降解析
    ├── parser.mbt              # 策略解析 (parse_policies, scope, conditions, annotations)
    ├── expr_wbtest.mbt         # 表达式解析测试
    └── parser_wbtest.mbt       # 策略解析测试
```

**总代码量**: ~4000 行 | **测试**: 274 个 (273 通过, 1 已知失败)

## 已完成

### AST 类型系统 ✓
- [x] `Expr` — 完整 Cedar 表达式 AST (16 种节点: Lit, Var, If, And, Or, UnaryApp, BinaryApp, GetAttr, HasAttr, Like, Is, Set, Record, ExtensionApp, Slot, Unknown)
- [x] `Policy` — 策略结构体 (id, effect, annotations, principal, action, resource, conditions)
- [x] `ScopeConstraint` — 6 种约束: All, Eq, In, Is, IsIn, InSet
- [x] `ConditionKind` / `Condition` / `Annotation` / `PolicyEffect`
- [x] 基础类型: EntityUID, EntityType, Name, Pattern, Type, Value, Entity, Request, Decision, AuthorizationResult

### Builder 模式 ✓
- [x] Expr 叶子构造器: `val_bool`, `val_long`, `val_str`, `val_euid`, `var_principal`, `var_action`, `var_resource`, `var_context`
- [x] Expr 非链式构造器: `if_`, `not_`, `neg`, `is_empty`, `set_`, `record_`, `ext_call`
- [x] Expr 链式方法 (22 个): `eq`, `ne`, `lt`, `le`, `gt`, `ge`, `add`, `sub`, `mul`, `and_`, `or_`, `in_`, `contains`, `contains_all`, `contains_any`, `get_tag`, `has_tag`, `access`, `has`, `like`, `is_`, `is_in`
- [x] Policy builder: `default()`, `permit`, `forbid`, 12 个 scope 方法, `with_id`, `annotate`, `when_`, `unless`
- [x] 辅助函数: `entity_uid()`, `entity_type()`
- [x] Builder 白盒测试覆盖

### 解析器 ✓
- [x] 词法分析 (`tokenize`): 关键字(11), 运算符(11), 字面量, 标识符, 符号
- [x] 表达式递归下降: 字面量 → 变量 → if-then-else → 成员访问 → 一元 → 二元 (正确优先级)
- [x] 策略解析 (`parse_policies`): 多策略, 注解, effect, scope, conditions
- [x] `@id("value")` 提取为策略 id 并从注解中移除
- [x] 无名策略自动编号: `"policy"` → `"policy1"` → `"policy2"`
- [x] 单个/多个策略解析测试 (使用 builder 构建预期值)

### 验证 ✓
- [x] `moon check`: 0 errors, 3 warnings (全部在 pony 包，既存)
- [x] `moon test`: 273/274 通过

## 已知问题

### 待修复
- [ ] **乘法结合性** (`parser/expr_wbtest.mbt:224`): `42 * 2 * 1` 解析为右结合 `(42 * (2 * 1))`，应为左结合 `((42 * 2) * 1)`。原因: `parse_mult` 递归向右，需要改为循环左结合

### 待实现 (按优先级)

1. **评估器 (Evaluator)**
   - 对 `Request` 求值 `Policy` → `Decision`
   - 实现 `BinaryOp` 和 `UnaryOp` 的求值逻辑
   - 实现 `Expr::If`, `Expr::And`, `Expr::Or` 短路求值
   - 实体属性/标签查找

2. **模板支持**
   - `Expr::Slot` 解析与模板实例化
   - 模板变量替换

3. **策略验证器**
   - 检查 scope variant 有效性 (principal 不支持 InSet, action 不支持 Is/IsIn)
   - 类型检查

4. **InSet scope 解析**
   - 目前 `action_in_set` builder 存在但解析器尚未支持 `action in [...]` 语法

5. **扩展函数**
   - IP, decimal 等扩展函数的实际求值 (目前解析但返回 opaque)

---

## 设计约定

- **命名**: `val_*` = 值字面量, `var_*` = PARC 变量; `_` 后缀仅用于 MoonBit 关键字冲突 (`and_`, `or_`, `in_`, `is_`, `if_`, `when_`)
- **Builder**: 方法直接定义在类型上 (无单独 Builder wrapper), Policy 用 `..` 功能记录更新
- **包结构**: `ast/` (类型 + builder), `parser/` (词法/语法分析), 同一 `ast` 包内文件可互相引用
