use egglog::{
    CommandOutput, EGraph, Term as EgglogTerm,
    ast::{Command, Expr, Literal},
};
use rustler::{Encoder, Env, NifMap, Term};

use crate::error::NativeError;

mod atoms {
    rustler::atoms! { literal, call, var, nil, nan, infinity, negative_infinity }
}

#[derive(NifMap)]
#[rustler(encode)]
pub struct Extraction {
    nodes: Vec<Node>,
    roots: Vec<Root>,
}

#[derive(NifMap)]
#[rustler(encode)]
struct Root {
    root: usize,
    cost: u64,
}

struct Node(EgglogTerm);

impl Encoder for Node {
    fn encode<'a>(&self, env: Env<'a>) -> Term<'a> {
        match &self.0 {
            EgglogTerm::App(name, children) => (atoms::call(), name, children).encode(env),
            EgglogTerm::Var(name) => (atoms::var(), name).encode(env),
            EgglogTerm::Lit(value) => {
                let value = match value {
                    Literal::Int(value) => value.encode(env),
                    Literal::Float(value) if value.0.is_finite() => value.0.encode(env),
                    Literal::Float(value) if value.0.is_nan() => atoms::nan().encode(env),
                    Literal::Float(value) if value.0.is_sign_negative() => {
                        atoms::negative_infinity().encode(env)
                    }
                    Literal::Float(_) => atoms::infinity().encode(env),
                    Literal::String(value) => value.encode(env),
                    Literal::Bool(value) => value.encode(env),
                    Literal::Unit => atoms::nil().encode(env),
                };
                (atoms::literal(), value).encode(env)
            }
        }
    }
}

pub fn extract(
    graph: &mut EGraph,
    expr: &str,
    variants: Option<i64>,
) -> Result<Extraction, NativeError> {
    let expr = graph.parser.get_expr_from_string(None, expr)?;
    let span = expr.span();
    let count = Expr::Lit(span.clone(), Literal::Int(variants.unwrap_or(0)));
    let (dag, roots) = graph
        .run_program(vec![Command::Extract(span, expr, count)])?
        .into_iter()
        .find_map(|output| match output {
            CommandOutput::ExtractBest(dag, cost, root) => Some((dag, vec![Root { root, cost }])),
            CommandOutput::ExtractVariants(dag, terms) => Some((
                dag,
                terms
                    .into_iter()
                    .map(|term| Root {
                        root: term.term,
                        cost: term.cost,
                    })
                    .collect(),
            )),
            _ => None,
        })
        .ok_or_else(|| egglog::Error::ExtractError("no extraction output".into()))?;
    Ok(Extraction {
        nodes: (0..dag.size())
            .map(|id| Node(dag.get(id).clone()))
            .collect(),
        roots,
    })
}
