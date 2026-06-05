use std::time::Instant;

use egglog::{EGraph, ast::Command};

use crate::report::{add_output_report_stats, collect_reports, output_kind};
use crate::snapshot::{NativeSnapshot, build_snapshot};

pub type NativeRun = (
    Vec<(String, String)>,
    Vec<(String, i64)>,
    Vec<(String, String)>,
    NativeSnapshot,
    Vec<(String, Vec<(String, i64)>)>,
);

pub fn execute_program(
    egraph: &mut EGraph,
    program: &str,
    started: Instant,
    snapshot_format: &str,
    snapshot_max_functions: i64,
    snapshot_max_calls_per_function: i64,
    snapshot_inline_leaves: i64,
    snapshot_split_primitive_outputs: bool,
) -> Result<NativeRun, String> {
    let commands = if program.trim().is_empty() {
        Vec::new()
    } else {
        egraph
            .parse_program(None, program)
            .map_err(|err| err.to_string())?
    };

    execute_commands(
        egraph,
        commands,
        started,
        snapshot_format,
        snapshot_max_functions,
        snapshot_max_calls_per_function,
        snapshot_inline_leaves,
        snapshot_split_primitive_outputs,
    )
}

pub fn execute_commands(
    egraph: &mut EGraph,
    commands: Vec<Command>,
    started: Instant,
    snapshot_format: &str,
    snapshot_max_functions: i64,
    snapshot_max_calls_per_function: i64,
    snapshot_inline_leaves: i64,
    snapshot_split_primitive_outputs: bool,
) -> Result<NativeRun, String> {
    let outputs = if commands.is_empty() {
        Vec::new()
    } else {
        egraph
            .run_program(commands)
            .map_err(|err| err.to_string())?
    };

    let mut numeric_stats = vec![
        (
            "elapsed_native_us".to_string(),
            started.elapsed().as_micros() as i64,
        ),
        ("num_tuples".to_string(), egraph.num_tuples() as i64),
        ("output_count".to_string(), outputs.len() as i64),
    ];

    add_output_report_stats(&outputs, &mut numeric_stats);
    let report = collect_reports(&outputs);

    let encoded_outputs = outputs
        .iter()
        .map(|output| (output_kind(output).to_string(), output.to_string()))
        .collect();

    let snapshot = build_snapshot(
        egraph,
        snapshot_format,
        snapshot_max_functions,
        snapshot_max_calls_per_function,
        snapshot_inline_leaves,
        snapshot_split_primitive_outputs,
    )?;

    Ok((encoded_outputs, numeric_stats, Vec::new(), snapshot, report))
}
