# Conventions

Naming conventions:
- Globals are `UPPER_CASE`
- Classes, Singletons, Structures, Types are `PascalCase`
- Acronyms are `UPPERCASE`, like `HTTP`.
- Functions, methods and parameters are `camelCase`
- Class methods should be `CamelCase`
- Local variables are `snake_case`
- Short lived variables should be short (`i`, `k`, `v`, `r`)
- Long lived variables should be long (`encryption_format`)

Coding style:
- Be concise and write compact code, only write comments to clarify your intent.
- Write short docstrings for all elements.
- Prefer functional over imperative

Implementation Style:
- Favor the use of the standard library .
- Minimise the use of third party libraries.
- Define interfaces when using third party libraries so that they can be swapper later.

