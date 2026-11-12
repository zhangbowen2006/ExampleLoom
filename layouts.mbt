///|
/// An explicitly declared source layout. The predicate and expressions bind
/// by recipe.columns; every rule must produce the same canonical output names.
pub(all) struct LayoutRule {
  name : String
  when : Condition
  recipe : Recipe
}

///|
fn validate_layout_rules(rules : Array[LayoutRule]) -> Unit raise LoomError {
  if rules.is_empty() || rules.length() > 16 {
    raise LoomError("normalize_layouts requires 1..16 rules")
  }
  validate_columns(rules.map(r => r.name))
  let output_names = rules[0].recipe.outputs.map(o => o.name)
  for rule in rules {
    ignore(recipe_to_json(rule.recipe))
    ignore(condition_to_json(rule.when))
    condition_fields(rule.when, rule.recipe.columns.length())
    if rule.recipe.columns.length() > 16 || rule.recipe.outputs.length() > 8 {
      raise LoomError("layout rule exceeds 16 inputs or 8 outputs")
    }
    if rule.recipe.outputs.map(o => o.name) != output_names {
      raise LoomError("layout rules require identical canonical output names")
    }
  }
}

///|
fn layout_rules_to_json(rules : Array[LayoutRule]) -> Json raise LoomError {
  validate_layout_rules(rules)
  Json::array(
    rules.map(rule => {
      Json::object({
        "name": Json(rule.name),
        "when": condition_to_json(rule.when),
        "recipe": recipe_to_json(rule.recipe),
      })
    }),
  )
}

///|
fn layout_rules_from_json(value : Json) -> Array[LayoutRule] raise LoomError {
  let rules = j_array(value).map(v => {
    let obj = j_object(v)
    fields_only(obj, ["name", "when", "recipe"])
    LayoutRule::{
      name: j_text(required(obj, "name")),
      when: condition_from_json(required(obj, "when")),
      recipe: recipe_from_json(required(obj, "recipe")),
    }
  })
  validate_layout_rules(rules)
  rules
}

///|
/// No match and multiple matches are errors. Predicate errors are propagated,
/// never treated as permission to fall through to a different layout.
fn normalize_layouts(
  table : Table,
  rules : Array[LayoutRule],
) -> Table raise LoomError {
  validate_layout_rules(rules)
  if table.rows.length() * rules.length() > 200000 {
    raise LoomError("layout routing exceeds 200000 row-rule checks")
  }
  let bindings : Array[Array[Int32]?] = rules.map(rule => {
    let indices : Array[Int32] = []
    for name in rule.recipe.columns {
      let index = Some(column_index(table, name)) catch { LoomError(_) => None }
      guard index is Some(i) else { return None }
      indices.push(i)
    }
    Some(indices)
  })
  if bindings.all(b => b is None) {
    raise LoomError("no layout has all required input columns")
  }
  let output_names = rules[0].recipe.outputs.map(o => o.name)
  check_growth(table.rows.length(), output_names.length())
  let rows : Array[Array[String]] = []
  let mut output_units = 0
  for ordinal, row in table.rows {
    let mut selected : (Int32, Array[String])? = None
    for i, rule in rules {
      guard bindings[i] is Some(indices) else { continue }
      let input = indices.map(j => row[j])
      let matches = test_condition(rule.when, input) catch {
        LoomError(message) =>
          raise LoomError("row \{ordinal+1}, layout \{rule.name}: \{message}")
      }
      if matches {
        if selected is Some((previous, _)) {
          raise LoomError(
            "row \{ordinal+1} matches both layouts \{rules[previous].name} and \{rule.name}",
          )
        }
        selected = Some((i, input))
      }
    }
    guard selected is Some((i, input)) else {
      raise LoomError("row \{ordinal+1} matches no declared layout")
    }
    let values = rules[i].recipe.outputs.map(o => evaluate(o.expression, input)) catch {
      LoomError(message) =>
        raise LoomError("row \{ordinal+1}, layout \{rules[i].name}: \{message}")
    }
    output_units += values.fold(init=0, (n, s) => n + s.length())
    if output_units > 2000000 {
      raise LoomError("layout output exceeds 2000000 UTF-16 units")
    }
    rows.push(values)
  }
  { columns: output_names, rows, }
}
