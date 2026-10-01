use egglog::{
    EGraph, RawValues, Read, Value,
    ast::FunctionSubtype,
    sort::{F, Q, S, Z},
};

use crate::error::NativeError;

pub type NativeValue = (String, String, String);

pub fn eval_expr(egraph: &mut EGraph, expr: &str) -> Result<NativeValue, NativeError> {
    let parsed = egraph
        .parser
        .get_expr_from_string(None, expr)
        .map_err(|err| NativeError::Native(err.to_string()))?;
    let (sort, value) = egraph
        .eval_expr(&parsed)
        .map_err(|err| NativeError::Native(err.to_string()))?;
    Ok(encode_value(egraph, sort.name(), value))
}

pub fn lookup_function(
    egraph: &mut EGraph,
    name: &str,
    arg_exprs: Vec<String>,
) -> Result<Option<NativeValue>, NativeError> {
    let (input_sort_names, output_sort_name, subtype) = {
        let schema = egraph
            .get_function(name)
            .ok_or_else(|| NativeError::Native(format!("could not find function {name}")))?
            .func_type();

        let input_sort_names = schema
            .input
            .iter()
            .map(|sort| sort.name().to_string())
            .collect::<Vec<_>>();

        (
            input_sort_names,
            schema.output.name().to_string(),
            schema.subtype,
        )
    };

    if arg_exprs.len() != input_sort_names.len() {
        return Err(NativeError::Native(format!(
            "function {name} expects {} arguments, got {}",
            input_sort_names.len(),
            arg_exprs.len()
        )));
    }

    let mut key = Vec::with_capacity(arg_exprs.len());

    for (expr, expected_sort) in arg_exprs.into_iter().zip(input_sort_names.iter()) {
        let parsed = egraph
            .parser
            .get_expr_from_string(None, &expr)
            .map_err(|err| NativeError::Native(err.to_string()))?;
        let (sort, value) = egraph
            .eval_expr(&parsed)
            .map_err(|err| NativeError::Native(err.to_string()))?;

        if sort.name() != expected_sort {
            return Err(NativeError::Native(format!(
                "function {name} expected argument {expr} to have sort {expected_sort}, got {}",
                sort.name()
            )));
        }

        key.push(value);
    }

    let value = egraph.read(|state| match subtype {
        FunctionSubtype::Custom => state.lookup(name, RawValues(key)),
        FunctionSubtype::Constructor => state.eclass_of(name, RawValues(key)),
    })?;
    Ok(value.map(|value| encode_value(egraph, &output_sort_name, value)))
}

pub type NativeFunction = (String, Vec<String>, String, String, bool, bool, bool);

pub fn function_info(function: &egglog::Function) -> NativeFunction {
    let schema = function.func_type();
    (
        function.name().to_owned(),
        schema
            .input
            .iter()
            .map(|sort| sort.name().to_owned())
            .collect(),
        schema.output.name().to_owned(),
        match schema.subtype {
            FunctionSubtype::Custom => "function",
            FunctionSubtype::Constructor => "constructor",
        }
        .to_owned(),
        function.is_hidden(),
        function.is_let_binding(),
        function.can_subsume(),
    )
}

pub fn functions(graph: &EGraph) -> Vec<NativeFunction> {
    graph
        .functions_iter()
        .map(|(_, function)| function_info(function))
        .collect()
}

pub type NativeBindings = Vec<Vec<(String, NativeValue)>>;

pub fn query(
    graph: &mut EGraph,
    vars: Vec<(String, String)>,
    facts: Vec<String>,
) -> Result<NativeBindings, NativeError> {
    let vars = vars
        .into_iter()
        .map(|(name, sort)| {
            graph
                .get_sort_by_name(&sort)
                .cloned()
                .map(|sort| (name, sort))
                .ok_or_else(|| NativeError::Native(format!("unknown sort {sort}")))
        })
        .collect::<Result<Vec<_>, _>>()?;
    let facts = facts
        .into_iter()
        .map(|fact| {
            graph
                .parser
                .get_fact_from_string(None, &fact)
                .map_err(|error| NativeError::Native(error.to_string()))
        })
        .collect::<Result<Vec<_>, _>>()?;
    let bindings = vars
        .iter()
        .map(|(name, sort)| (name.as_str(), sort.clone()))
        .collect::<Vec<_>>();
    let rows = graph.query(&bindings, egglog::ast::Facts(facts))?;
    Ok(rows
        .into_iter()
        .map(|row| {
            vars.iter()
                .map(|(name, sort)| (name.clone(), encode_value(graph, sort.name(), row[name])))
                .collect()
        })
        .collect())
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
