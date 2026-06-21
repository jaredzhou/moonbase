# MoonCedar 项目申报书

**项目名称**：MoonCedar — Cedar 策略引擎的 MoonBit 移植
**参赛者**：jaredzhou　　　**联系方式**：18918321024
**GitHub**：https://github.com/jaredzhou/moonbase（mooncedar 模块）
**示例应用（TinyTodo）**：同上（todo 模块）— 基于 MoonCedar + pony 的多用户待办应用
**项目方向**：MoonBit 授权与访问控制引擎　　　**是否移植**：是

MoonCedar 将 AWS 开源的 Cedar 策略语言引擎（Amazon Verified Permissions 核心）移植到 MoonBit 生态，为 MoonBit Web 应用、微服务、边缘计算提供与 Cedar 兼容的细粒度访问控制（RBAC + ABAC）。项目已实现完整的策略解析器（lexer + 递归下降 parser）、18 种表达式节点 AST、链式 builder 模式、trait-based 可插拔实体存储、partial evaluation 和 JSON 序列化，546+ 测试用例。作为 MoonBit 生态首个访问控制引擎，可用于 pony Web 框架授权中间件、微服务 PDP、对象存储权限控制等场景，为 MoonBit BaaS 生态提供基础能力。

**核心功能范围**：
- **parser 子包**：完整 Cedar 策略语法解析（11 关键字 + 11 操作符），递归下降，多策略批量解析
- **ast 子包**：18 种 Expr 节点、Entity/Policy/Value 类型，策略校验（`validate_policies`），链式 builder
- **stringify**：AST 到 Cedar 源码完整序列化，9 级运算符优先级
- **evaluator 子包**：18 种表达式节点求值（12 二元 + 3 一元操作符），wildcard/scope 匹配，partial evaluation
- **可插拔实体存储**：`EntityStore` trait + `MapEntityStore`，实体层级 BFS 查找
- **authorizer**：`evaluate`/`reauthorize`/`concretize`/`is_authorized`，Allow/Deny + Diagnostic
- **JSON 序列化**：EntityUID/Entity/Value/MapEntityStore Cedar 兼容导入导出
- **测试**：546+ 用例，黑白盒分离（`_test.mbt` + `_wbtest.mbt`），快照 + 断言
- **示例**：TinyTodo 应用展示 MoonCedar + pony 端到端授权集成

**移植参考说明**：
原项目：Cedar（cedar-policy）　|　https://github.com/cedar-policy/cedar
原项目许可证：Apache 2.0　　本项目许可证：Apache 2.0

与原 Rust 实现的简化与重新设计：
- 优先实现核心策略评估，弱化 schema/validator/formatter/CLI 等外围工具链
- 纯函数式递归下降 parser（无外部依赖），从零适配 MoonBit 字符串与错误语义
- 表达式求值以 MoonBit 数值类型重写（含溢出检查），标准库重构字符串/集合/记录操作
- Partial evaluation 以 MoonBit 模式匹配实现，将 AST `Unknown` 替换为 PARC 残留表达式
- 后续扩展：TPE batch authorizer / sqlizer；暂不实现 schema 验证、extension function（IP/decimal）、slot instantiation
