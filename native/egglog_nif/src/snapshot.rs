use egglog::{EGraph, SerializeConfig};

pub type NativeSnapshot = (String, String, String, Vec<(String, i64)>);

pub fn build_snapshot(
    egraph: &EGraph,
    snapshot_format: &str,
    max_functions: i64,
    max_calls_per_function: i64,
    inline_leaves: i64,
    split_primitive_outputs: bool,
) -> Result<NativeSnapshot, String> {
    match snapshot_format {
        "" | "none" => Ok((String::new(), String::new(), String::new(), Vec::new())),
        "dot" | "json" => {
            let serialize_output = egraph.serialize(SerializeConfig {
                max_functions: positive_limit(max_functions),
                max_calls_per_function: positive_limit(max_calls_per_function),
                ..SerializeConfig::default()
            });
            let omitted = serialize_output.omitted_description();
            let mut serialized = serialize_output.egraph;

            if split_primitive_outputs {
                serialized.split_classes(|id, _| egraph.from_node_id(id).is_primitive());
            }

            for _ in 0..inline_leaves.max(0) {
                serialized.inline_leaves();
            }

            let stats = vec![
                ("snapshot_nodes".to_string(), serialized.nodes.len() as i64),
                (
                    "snapshot_classes".to_string(),
                    serialized.class_data.len() as i64,
                ),
            ];

            let text = match snapshot_format {
                "dot" => serialized.to_dot(),
                "json" => {
                    serde_json::to_string_pretty(&serialized).map_err(|err| err.to_string())?
                }
                _ => unreachable!(),
            };

            Ok((snapshot_format.to_string(), text, omitted, stats))
        }
        other => Err(format!("unsupported snapshot format: {other}")),
    }
}

fn positive_limit(value: i64) -> Option<usize> {
    if value > 0 {
        Some(value as usize)
    } else {
        None
    }
}
