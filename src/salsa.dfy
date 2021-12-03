type Filename = string

datatype Ast = Const(int) | Plus(Ast, Ast)

datatype Option<T> = None | Some(value: T)

function GoldWholeProgram(manifest: seq<Filename>,
                          source_texts: map<Filename, Memo<string>>): seq<Ast>
  requires forall f :: f in manifest ==> f in source_texts.Keys
{
  if manifest == [] then
    []
  else
    var file := manifest  [0];
    var ast := GoldAst(source_texts, file);
    [ast] + GoldWholeProgram(manifest[1..], source_texts)
}

function GoldAst(source_texts: map<Filename, Memo<string>>, filename: Filename): Ast
requires filename in source_texts
{
    Parse(source_texts[filename].value)
}

function method Parse(source: string): Ast {
  if source == "" then Const(0) else Const(1)
}

type Revision = nat

datatype Dependency =
  | Manifest
  | SourceText(string)
  | Ast(string)
  | WholeProgramAst

datatype Memo<V> = Memo(verified_at: Revision,
                        changed_at: Revision,
                        deps: seq<Dependency>,
                        value: V)
{
  predicate ValidAt(revision: Revision) {
    verified_at <= revision &&
    changed_at <= revision
  }

  predicate ValidBaseInputAt(revision: Revision) {
    verified_at == changed_at <= revision
  }

  static function method Input(revision: Revision, value: V): Memo<V> {
    Memo(revision, revision, [], value)
  }
}

class Database {
  var manifest: Memo<seq<Filename>>
  var source_texts: map<Filename, Memo<string>>
  var asts: map<Filename, Memo<Ast>>
  var whole_program: Option<Memo<seq<Ast>>>
  var current_revision: Revision

  predicate Valid()
    reads this
  {
    && (forall filename :: filename in manifest.value ==>
           filename in source_texts.Keys)
    && manifest.ValidBaseInputAt(current_revision)
    && (forall filename :: filename in source_texts.Keys ==>
          source_texts[filename].ValidBaseInputAt(current_revision))
    && (forall filename :: filename in asts.Keys ==>
          asts[filename].ValidAt(current_revision))
    && (whole_program == None ||
        whole_program.value.ValidAt(current_revision))
    && (forall filename :: filename in asts.Keys && asts[filename].verified_at == current_revision ==>
        filename in source_texts.Keys)
    && (forall filename :: filename in asts.Keys && asts[filename].verified_at == current_revision ==>
        asts[filename].value == GoldAst(source_texts, filename))
    && (whole_program.Some? ==> whole_program.value.verified_at == current_revision ==>
        GoldWholeProgram(manifest.value, source_texts) == whole_program.value.value)
  }

  twostate predicate InputsDon'tChange()
    reads this
  {
    && manifest == old(manifest)
    && source_texts == old(source_texts)
  }

  constructor () {
    manifest := Memo.Input(0, []);
    source_texts := map[];
    asts := map[];
    whole_program := None;
    current_revision := 0;
  }

  // Extend manifest and set file, or update file if already present
  method AddFile(filename: Filename, source: string)
    requires Valid()
    modifies this
    ensures Valid()
  {
    current_revision := current_revision + 1;

    if filename !in manifest.value {
      manifest := Memo.Input(current_revision, manifest.value + [filename]);
    }

    source_texts := source_texts[filename := Memo.Input(current_revision, source)];
  }

  method Ast(filename: Filename) returns (ast: Ast)
    requires Valid() && filename in manifest.value
    modifies this
    ensures Valid() && InputsDon'tChange() && filename in asts.Keys
  {
    var old_memo: Option<Memo<Ast>> := None;
    if filename in asts.Keys {
/* fixme: potential reuse */
    }

    var deps := [SourceText(filename)];
    var changed_at := source_texts[filename].changed_at;
    var text := source_texts[filename].value;
    ast := Parse(text);

    // Backdate if you have an old memo and it has not changed
    if old_memo.Some? && old_memo.value.value == ast {
      changed_at := old_memo.value.changed_at;
    }

    asts := asts[filename := Memo(current_revision, changed_at, deps, ast)];
  }

  method WholeProgramAst() returns (result: seq<Ast>)
    requires Valid()
    modifies this
    ensures Valid() && InputsDon'tChange() && whole_program.Some?
    // ensures result == GoldWholeProgram()...
  {
    var old_memo: Option<Memo<seq<Ast>>> := this.whole_program;
    if whole_program.Some? {
      /* fixme: potential reuse */
    }

    var deps := [Manifest];
    var changed_at: Revision := manifest.changed_at;

    result := [];
    for i := 0 to |manifest.value|
      invariant Valid() && InputsDon'tChange()
      invariant changed_at <= current_revision
    {
      var filename := manifest.value[i];
      var value := Ast(filename);

      // record dependency:
      deps := deps + [Dependency.Ast(filename)];
      changed_at := min(changed_at, this.asts[filename].changed_at);

      result := result + [value];
    }
    
    // Backdate if you have an old memo and it has not changed
    if whole_program.Some? && whole_program.value.value == result {
      changed_at := whole_program.value.changed_at;
    }

    whole_program := Some(Memo(current_revision, changed_at, deps, result));
  }
}

function method min(x: Revision, y: Revision): Revision { // thank you :)
  if x < y then x else y
}
