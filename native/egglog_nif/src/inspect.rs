use egglog::{
    EGraph, Value,
    sort::{F, Q, S, Z},
};

pub type NativeValue = (String, String, String);

pub fn eval_expr(egraph: &mut EGraph, expr: &str) -> Result<NativeValue, String> {
    let parsed = egraph
        .parser
        .get_expr_from_string(None, expr)
        .map_err(|err| err.to_string())?;
    let (sort, value) = egraph.eval_expr(&parsed).map_err(|err| err.to_string())?;
    Ok(encode_value(egraph, sort.name(), value))
}

pub fn lookup_function(
    egraph: &mut EGraph,
    name: &str,
    arg_exprs: Vec<String>,
) -> Result<Option<NativeValue>, String> {
    let (input_sort_names, output_sort_name) = {
        let schema = egraph
            .get_function(name)
            .ok_or_else(|| format!("could not find function {name}"))?
            .schema();

        let input_sort_names = schema
            .input
            .iter()
            .map(|sort| sort.name().to_string())
            .collect::<Vec<_>>();

        (input_sort_names, schema.output.name().to_string())
    };

    if arg_exprs.len() != input_sort_names.len() {
        return Err(format!(
            "function {name} expects {} arguments, got {}",
            input_sort_names.len(),
            arg_exprs.len()
        ));
    }

    let mut key = Vec::with_capacity(arg_exprs.len());

    for (expr, expected_sort) in arg_exprs.into_iter().zip(input_sort_names.iter()) {
        let parsed = egraph
            .parser
            .get_expr_from_string(None, &expr)
            .map_err(|err| err.to_string())?;
        let (sort, value) = egraph.eval_expr(&parsed).map_err(|err| err.to_string())?;

        if sort.name() != expected_sort {
            return Err(format!(
                "function {name} expected argument {expr} to have sort {expected_sort}, got {}",
                sort.name()
            ));
        }

        key.push(value);
    }

    Ok(egraph
        .lookup_function(name, &key)
        .map(|value| encode_value(egraph, &output_sort_name, value)))
}

fn encode_value(egraph: &EGraph, sort: &str, value: Value) -> NativeValue {
    match sort {
        "i64" => (
            sort.to_string(),
            "integer".to_string(),
            egraph.value_to_base::<i64>(value).to_string(),
        ),
        "f64" => (
            sort.to_string(),
            "float".to_string(),
            egraph.value_to_base::<F>(value).0.into_inner().to_string(),
        ),
        "String" => (
            sort.to_string(),
            "string".to_string(),
            egraph.value_to_base::<S>(value).0,
        ),
        "bool" => (
            sort.to_string(),
            "boolean".to_string(),
            egraph.value_to_base::<bool>(value).to_string(),
        ),
        "Unit" => (sort.to_string(), "unit".to_string(), String::new()),
        "BigInt" => (
            sort.to_string(),
            "integer_string".to_string(),
            egraph.value_to_base::<Z>(value).0.to_string(),
        ),
        "BigRat" => (
            sort.to_string(),
            "rational_string".to_string(),
            egraph.value_to_base::<Q>(value).0.to_string(),
        ),
        _ => (sort.to_string(), "value".to_string(), format!("{value:?}")),
    }
}
