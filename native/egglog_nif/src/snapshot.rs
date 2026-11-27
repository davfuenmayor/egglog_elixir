use egglog::{EGraph, SerializeConfig};
use rustler::NifMap;

#[derive(Default, NifMap)]
#[rustler(encode)]
pub struct SnapshotData {
    dot: Option<String>,
    json: Option<String>,
    complete: bool,
    truncated_functions: Vec<String>,
    discarded_functions: Vec<String>,
}

pub type NativeSnapshot = (String, String, Vec<(String, i64)>, SnapshotData);

pub fn build_snapshot(
    egraph: &EGraph,
    snapshot_format: &str,
    max_functions: i64,
    max_calls_per_function: i64,
    inline_leaves: i64,
    split_primitive_outputs: bool,
) -> Result<NativeSnapshot, String> {
    if matches!(snapshot_format, "" | "none") {
        return Ok((
            String::new(),
            String::new(),
            Vec::new(),
            SnapshotData::default(),
        ));
    }
    if !matches!(snapshot_format, "dot" | "json") {
        return Err(format!("unsupported snapshot format: {snapshot_format}"));
    }
    let output = egraph.serialize(SerializeConfig {
        max_functions: positive_limit(max_functions),
        max_calls_per_function: positive_limit(max_calls_per_function),
        ..SerializeConfig::default()
    });
    let omitted = output.omitted_description();
    let complete = output.is_complete();
    let mut graph = output.egraph;
    if split_primitive_outputs {
        graph.split_classes(|id, _| egraph.from_node_id(id).is_primitive());
    }
    for _ in 0..inline_leaves.max(0) {
        graph.inline_leaves();
    }
    let stats = vec![
        ("snapshot_nodes".to_string(), graph.nodes.len() as i64),
        (
            "snapshot_classes".to_string(),
            graph.class_data.len() as i64,
        ),
    ];
    let dot = graph.to_dot();
    let json = serde_json::to_string_pretty(&graph).map_err(|err| err.to_string())?;
    Ok((
        snapshot_format.to_owned(),
        omitted,
        stats,
        SnapshotData {
            dot: Some(dot),
            json: Some(json),
            complete,
            truncated_functions: output.truncated_functions,
            discarded_functions: output.discarded_functions,
        },
    ))
}

fn positive_limit(value: i64) -> Option<usize> {
    if value > 0 {
        Some(value as usize)
    } else {
        None
    }
}
