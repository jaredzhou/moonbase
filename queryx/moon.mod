// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "jaredzhou/queryx"

version = "0.2.0"

readme = "README.mbt.md"

repository = "https://github.com/jaredzhou/moonbase"

license = "Apache-2.0"

keywords = [ "query", "filter", "json", "dsl" ]

preferred_target = "native"

description = "JSON-queryable filter DSL with foxql SQL builder bridge"

import {
  "jaredzhou/foxql@0.1.2",
}
