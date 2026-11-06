use std::{error::Error, fs, path::PathBuf};

fn main() -> Result<(), Box<dyn Error>> {
    let directory = PathBuf::from(
        std::env::args()
            .nth(1)
            .ok_or("pass the captured corpus directory")?,
    );
    for entry in fs::read_dir(directory)? {
        let path = entry?.path();
        if path.extension().is_none_or(|extension| extension != "json") {
            continue;
        }
        let mut json: serde_json::Value = serde_json::from_str(&fs::read_to_string(&path)?)?;
        // Native serde serializes non-finite extraction costs as null. The DOT
        // exporter never uses costs; supply a finite placeholder only so its
        // JSON reader can load the otherwise unchanged labelled graph.
        if let Some(nodes) = json
            .get_mut("nodes")
            .and_then(|nodes| nodes.as_object_mut())
        {
            for node in nodes.values_mut() {
                if node.get("cost").is_some_and(|cost| cost.is_null()) {
                    node["cost"] = serde_json::json!(0.0);
                }
            }
        }
        let graph: egraph_serialize::EGraph = serde_json::from_value(json)?;
        fs::write(path.with_extension("dot"), graph.to_dot())?;
        println!("DOT {}: {} nodes", path.display(), graph.nodes.len());
    }
    Ok(())
}
