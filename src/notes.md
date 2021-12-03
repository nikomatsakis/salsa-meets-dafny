# Salsa Meets Dafny

## Salsa overview

* Queries:
    * Input queries 
    * Derived queries
    
```rust
let mut db = MyDatabase::new();

// "Set" the input to something
db.set_source_file("fn main() { }");

let out = db.compiled_out();
//           ^^^^^^^^^^^^

db.set_source_file("fn main() { /* Foo */ }");

let out = db.compiled_out();
```


## Example from salsa video (https://www.youtube.com/watch?v=i_IhACacPRY)

```rust
#[salsa::query_group(InputsStorage)]
pub trait MyQueryGroup {
  #[salsa::input] // `set_manifest` is auto-generated
  fn manifest(&self) -> Manifest;

  #[salsa::input] // `set_source_text` is auto-generated
  fn source_text(&self, name: String) -> String;

  fn ast(&self, name: String) -> Ast;

  fn whole_program_ast(&self) -> Ast;
}

fn ast(db: &dyn MyQueryGroup, name: String) -> Ast {
  let source_text: String = db.source_text(name);
  // do the actual parser on `source_text`
  return ast;
}

fn whole_program_ast(db: &dyn MyQueryGroup) -> Ast {
  let mut ast = Ast::default();
  for source_file in db.manifest() {
    let ast_source_file = db.ast(source_file);
    ast.extend(ast_source_file);
  }
  return ast;
}

/*
enum Dependency {
    Manifest(),
    SourceText(String),
    Ast(String),
    WholeProgramAst(),
}
*/

fn main() {
    let mut db = .... // db is R0
    
    db.set_manifest(Manifest { file: "a.rs" }); // creates R1
    db.set_source_text("a.rs", "...."); // creates R2
    db.whole_program_ast();
    
    /* Db is in R2
    
    manifest: () -> (Manifest, changed_at: R1)
    source_text: "a.rs" -> ("....", changed_at: R2)
    ast: "a.rs" -> (Ast, verified_at: R2, changed_at: R2, deps: [Dependency::SourceText("a.rs")])
    whole_program_ast: () -> (Ast, verified_at: R2, changed_at: R2, deps: [
        Dependency::Manifest, 
        Dependency::Ast("a.rs"),
    ])
    
    */
    
    db.set_source_text("a.rs", ".... /* comment */"); // creates R3
    
      
    /* Db is in R3
    
    manifest: () -> (Manifest, changed_at: R1)
    source_text: "a.rs" -> ("....", changed_at: R3)
    ast: "a.rs" -> (Ast, verified_at: R3, changed_at: R2, deps: [Dependency::SourceText("a.rs")])
    whole_program_ast: () -> (Ast, verified_at: R3, changed_at: R2, deps: [
        Dependency::Manifest, 
        Dependency::Ast("a.rs"),
    ])
    
    */
    
    db.whole_program_ast();
    
    db.set_manifest(Manifest { file: "b.rs" }); // creates R1
    db.delete_source_text("a.rs")
    db.set_source_text("b.rs", ".... /* comment */"); // creates R3

    /* Db is in R3
    
    manifest: () -> (Manifest, changed_at: R1)
    source_text: "b.rs" -> ("....", changed_at: R3)
    ast: 
        "a.rs" -> (Ast, verified_at: R2, changed_at: R2, deps: [Dependency::SourceText("a.rs")])
        "b.rs" -> (Ast, verified_at: R3, changed_at: R2, deps: [Dependency::SourceText("a.rs")])
    whole_program_ast: () -> (Ast, verified_at: R3, changed_at: R2, deps: [
        Dependency::Manifest, 
        Dependency::Ast("b.rs"),
    ])
    
    */
    
}
```

Database contains a hashmap per query

* manifest
    * `() -> (Manifest, changed_at: Revision)`
* source_text
    * `String -> (String, changed_at: Revision)`
* ast
    * `String -> (Ast, verified_at: Revision, changed_at: Revision, dependencies: [Dep])`
* whole_program_ast
    * () -> `Ast`
    