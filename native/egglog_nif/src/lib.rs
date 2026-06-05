use std::panic::{AssertUnwindSafe, catch_unwind};
use std::sync::Mutex;
use std::time::Instant;

use egglog::EGraph;
use rustler::{Encoder, Env, ResourceArc, Term};

mod error;
mod inspect;
mod report;
mod resources;
mod run;
mod snapshot;

use error::NativeError;
use resources::{EGraphResource, ParsedProgramResource, ProgramInner, ProgramResource};
use run::{NativeRun, execute_commands, execute_program};

mod atoms {
    rustler::atoms! {
        ok,
        error,
        closed,
        invalid_theory,
        native_error
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
fn parse_program<'a>(env: Env<'a>, source: String) -> Term<'a> {
    respond(env, || {
        let mut egraph = EGraph::default();
        let commands = egraph
            .parse_program(None, &source)
            .map_err(|err| NativeError::InvalidTheory(err.to_string()))?;
        let count = commands.len() as i64;
        let resource = ResourceArc::new(ParsedProgramResource { commands });
        Ok((atoms::ok(), resource, count))
    })
}

#[rustler::nif(schedule = "DirtyCpu")]
fn load_program<'a>(env: Env<'a>, source: String, proofs: bool) -> Term<'a> {
    respond(env, || {
        let egraph = resources::load_egraph(&source, proofs).map_err(NativeError::InvalidTheory)?;
        let inner = ProgramInner {
            base: egraph,
        };
        let resource = ResourceArc::new(ProgramResource {
            inner: Mutex::new(Some(inner)),
        });
        Ok((atoms::ok(), resource))
    })
}

#[rustler::nif(schedule = "DirtyCpu")]
fn new_egraph<'a>(env: Env<'a>, source: String, proofs: bool) -> Term<'a> {
    respond(env, || {
        let egraph = resources::load_egraph(&source, proofs).map_err(NativeError::InvalidTheory)?;
        let resource = ResourceArc::new(EGraphResource {
            inner: Mutex::new(Some(egraph)),
        });
        Ok((atoms::ok(), resource))
    })
}

#[rustler::nif(schedule = "DirtyCpu")]
fn run_program<'a>(
    env: Env<'a>,
    program: ResourceArc<ProgramResource>,
    source: String,
    mode: String,
    snapshot_format: String,
    snapshot_max_functions: i64,
    snapshot_max_calls_per_function: i64,
    snapshot_inline_leaves: i64,
    snapshot_split_primitive_outputs: bool,
) -> Term<'a> {
    run_cloned_program(env, program, mode, |egraph, started| {
        execute_program(
            egraph,
            &source,
            started,
            &snapshot_format,
            snapshot_max_functions,
            snapshot_max_calls_per_function,
            snapshot_inline_leaves,
            snapshot_split_primitive_outputs,
        )
    })
}

#[rustler::nif(schedule = "DirtyCpu")]
fn run_parsed_program<'a>(
    env: Env<'a>,
    program: ResourceArc<ProgramResource>,
    parsed_program: ResourceArc<ParsedProgramResource>,
    mode: String,
    snapshot_format: String,
    snapshot_max_functions: i64,
    snapshot_max_calls_per_function: i64,
    snapshot_inline_leaves: i64,
    snapshot_split_primitive_outputs: bool,
) -> Term<'a> {
    run_cloned_program(env, program, mode, |egraph, started| {
        execute_commands(
            egraph,
            parsed_program.commands.clone(),
            started,
            &snapshot_format,
            snapshot_max_functions,
            snapshot_max_calls_per_function,
            snapshot_inline_leaves,
            snapshot_split_primitive_outputs,
        )
    })
}

#[rustler::nif(schedule = "DirtyCpu")]
fn run_egraph<'a>(
    env: Env<'a>,
    egraph: ResourceArc<EGraphResource>,
    program: String,
    snapshot_format: String,
    snapshot_max_functions: i64,
    snapshot_max_calls_per_function: i64,
    snapshot_inline_leaves: i64,
    snapshot_split_primitive_outputs: bool,
) -> Term<'a> {
    respond(env, || {
        let started = Instant::now();
        let run = resources::with_egraph_mut(&egraph, |egraph| {
            execute_program(
                egraph,
                &program,
                started,
                &snapshot_format,
                snapshot_max_functions,
                snapshot_max_calls_per_function,
                snapshot_inline_leaves,
                snapshot_split_primitive_outputs,
            )
        })?;
        Ok(native_run_response(run))
    })
}

#[rustler::nif(schedule = "DirtyCpu")]
fn run_parsed_egraph<'a>(
    env: Env<'a>,
    egraph: ResourceArc<EGraphResource>,
    parsed_program: ResourceArc<ParsedProgramResource>,
    snapshot_format: String,
    snapshot_max_functions: i64,
    snapshot_max_calls_per_function: i64,
    snapshot_inline_leaves: i64,
    snapshot_split_primitive_outputs: bool,
) -> Term<'a> {
    respond(env, || {
        let started = Instant::now();
        let run = resources::with_egraph_mut(&egraph, |egraph| {
            execute_commands(
                egraph,
                parsed_program.commands.clone(),
                started,
                &snapshot_format,
                snapshot_max_functions,
                snapshot_max_calls_per_function,
                snapshot_inline_leaves,
                snapshot_split_primitive_outputs,
            )
        })?;
        Ok(native_run_response(run))
    })
}

#[rustler::nif(schedule = "DirtyCpu")]
fn eval_program<'a>(
    env: Env<'a>,
    program: ResourceArc<ProgramResource>,
    source: String,
    expr: String,
) -> Term<'a> {
    respond(env, || {
        let (sort, kind, value) = resources::with_cloned_program(&program, |egraph| {
            run_input(egraph, &source)?;
            inspect::eval_expr(egraph, &expr)
        })?;

        Ok((atoms::ok(), sort, kind, value))
    })
}

#[rustler::nif(schedule = "DirtyCpu")]
fn eval_egraph<'a>(env: Env<'a>, egraph: ResourceArc<EGraphResource>, expr: String) -> Term<'a> {
    respond(env, || {
        let (sort, kind, value) =
            resources::with_egraph_mut(&egraph, |egraph| inspect::eval_expr(egraph, &expr))?;
        Ok((atoms::ok(), sort, kind, value))
    })
}

#[rustler::nif(schedule = "DirtyCpu")]
fn lookup_program<'a>(
    env: Env<'a>,
    program: ResourceArc<ProgramResource>,
    source: String,
    name: String,
    arg_exprs: Vec<String>,
) -> Term<'a> {
    respond(env, || {
        let value = resources::with_cloned_program(&program, |egraph| {
            run_input(egraph, &source)?;
            inspect::lookup_function(egraph, &name, arg_exprs)
        })?;

        Ok(native_lookup_response(value))
    })
}

#[rustler::nif(schedule = "DirtyCpu")]
fn lookup_egraph<'a>(
    env: Env<'a>,
    egraph: ResourceArc<EGraphResource>,
    name: String,
    arg_exprs: Vec<String>,
) -> Term<'a> {
    respond(env, || {
        let value = resources::with_egraph_mut(&egraph, |egraph| {
            inspect::lookup_function(egraph, &name, arg_exprs)
        })?;
        Ok(native_lookup_response(value))
    })
}

#[rustler::nif]
fn program_num_tuples<'a>(env: Env<'a>, program: ResourceArc<ProgramResource>) -> Term<'a> {
    respond(env, || {
        let count = resources::with_program(&program, |inner| {
            Ok((atoms::ok(), inner.base.num_tuples() as i64))
        })?;
        Ok(count)
    })
}

#[rustler::nif]
fn egraph_num_tuples<'a>(env: Env<'a>, egraph: ResourceArc<EGraphResource>) -> Term<'a> {
    respond(env, || {
        let count = resources::with_egraph(&egraph, |egraph| {
            Ok((atoms::ok(), egraph.num_tuples() as i64))
        })?;
        Ok(count)
    })
}

#[rustler::nif]
fn close_program<'a>(env: Env<'a>, program: ResourceArc<ProgramResource>) -> Term<'a> {
    respond(env, || {
        resources::close_program(&program)?;
        Ok(atoms::ok())
    })
}

#[rustler::nif]
fn close_egraph<'a>(env: Env<'a>, egraph: ResourceArc<EGraphResource>) -> Term<'a> {
    respond(env, || {
        resources::close_egraph(&egraph)?;
        Ok(atoms::ok())
    })
}

fn run_cloned_program<'a>(
    env: Env<'a>,
    program: ResourceArc<ProgramResource>,
    mode: String,
    fun: impl FnOnce(&mut EGraph, Instant) -> Result<NativeRun, String>,
) -> Term<'a> {
    respond(env, || {
        let mut run =
            resources::with_cloned_program(&program, |egraph| fun(egraph, Instant::now()))?;
        run.2.push(("mode".to_string(), mode));
        Ok(native_run_response(run))
    })
}

fn run_input(egraph: &mut EGraph, source: &str) -> Result<(), String> {
    if source.trim().is_empty() {
        Ok(())
    } else {
        execute_program(egraph, source, Instant::now(), "none", 0, 0, 0, false).map(|_run| ())
    }
}

fn native_run_response(
    run: NativeRun,
) -> (
    rustler::Atom,
    rustler::Atom,
    Vec<(String, String)>,
    Vec<(String, i64)>,
    Vec<(String, String)>,
    snapshot::NativeSnapshot,
    Vec<(String, Vec<(String, i64)>)>,
) {
    let (outputs, numeric_stats, text_stats, snapshot, report) = run;
    (
        atoms::ok(),
        atoms::ok(),
        outputs,
        numeric_stats,
        text_stats,
        snapshot,
        report,
    )
}

fn native_lookup_response(
    value: Option<inspect::NativeValue>,
) -> (rustler::Atom, bool, String, String, String) {
    match value {
        Some((sort, kind, value)) => (atoms::ok(), true, sort, kind, value),
        None => (
            atoms::ok(),
            false,
            String::new(),
            String::new(),
            String::new(),
        ),
    }
}

fn respond<'a, T>(env: Env<'a>, fun: impl FnOnce() -> Result<T, NativeError>) -> Term<'a>
where
    T: Encoder,
{
    match catch_unwind(AssertUnwindSafe(fun)) {
        Ok(Ok(value)) => value.encode(env),
        Ok(Err(error)) => error.encode(env),
        Err(payload) => NativeError::Native(error::panic_payload_to_string(payload)).encode(env),
    }
}

rustler::init!("Elixir.Egglog.Native");
