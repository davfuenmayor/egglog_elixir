use std::panic::{AssertUnwindSafe, catch_unwind};
use std::sync::Mutex;

use egglog::{EGraph, ast::Command};
use rustler::{Resource, ResourceArc};

use crate::error::NativeError;

pub struct ProgramInner {
    pub base: EGraph,
}

pub struct ProgramResource {
    // Per-resource guard only. This is not a process-wide scheduler lock:
    // it protects the lifetime of the base and serializes clone-local execution.
    pub inner: Mutex<Option<ProgramInner>>,
}

#[rustler::resource_impl]
impl Resource for ProgramResource {}

pub struct EGraphResource {
    // Mutable sessions are explicitly stateful. The Elixir side owns access
    // through one process; this guard protects the native resource itself.
    pub inner: Mutex<Option<EGraph>>,
}

#[rustler::resource_impl]
impl Resource for EGraphResource {}

pub struct ParsedProgramResource {
    pub commands: Vec<Command>,
}

#[rustler::resource_impl]
impl Resource for ParsedProgramResource {}

pub fn load_egraph(source: &str, proofs: bool) -> Result<EGraph, String> {
    let mut egraph = if proofs {
        EGraph::new_with_proofs()
    } else {
        EGraph::default()
    };

    if !source.trim().is_empty() {
        egraph
            .parse_and_run_program(None, source)
            .map_err(|err| err.to_string())?;
    }

    Ok(egraph)
}

pub fn with_cloned_program<T>(
    program: &ResourceArc<ProgramResource>,
    fun: impl FnOnce(&mut EGraph) -> Result<T, NativeError>,
) -> Result<T, NativeError> {
    with_cloned_base(&program.inner, fun)
}

fn with_cloned_base<T>(
    inner: &Mutex<Option<ProgramInner>>,
    fun: impl FnOnce(&mut EGraph) -> Result<T, NativeError>,
) -> Result<T, NativeError> {
    let guard = inner
        .lock()
        .map_err(|_| NativeError::Closed("program is unavailable after a native panic".into()))?;
    let inner = guard
        .as_ref()
        .ok_or_else(|| NativeError::Closed("program is closed".into()))?;
    // Unwind inside the lock scope so errors do not poison the reusable base.
    match catch_unwind(AssertUnwindSafe(|| {
        let mut egraph = inner.base.clone();
        fun(&mut egraph)
    })) {
        Ok(result) => result,
        Err(payload) => Err(NativeError::Panic(crate::error::panic_payload_to_string(
            payload,
        ))),
    }
}

pub fn with_program<T>(
    program: &ResourceArc<ProgramResource>,
    fun: impl FnOnce(&ProgramInner) -> Result<T, NativeError>,
) -> Result<T, NativeError> {
    let guard = program.inner.lock().map_err(|_| {
        NativeError::Closed("program is unavailable after a native panic".to_string())
    })?;

    let inner = guard
        .as_ref()
        .ok_or_else(|| NativeError::Closed("program is closed".to_string()))?;

    fun(inner)
}

pub fn with_egraph<T>(
    resource: &ResourceArc<EGraphResource>,
    fun: impl FnOnce(&EGraph) -> Result<T, NativeError>,
) -> Result<T, NativeError> {
    let guard = resource.inner.lock().map_err(|_| {
        NativeError::Closed("egraph is unavailable after a native panic".to_string())
    })?;

    let egraph = guard
        .as_ref()
        .ok_or_else(|| NativeError::Closed("egraph is closed".to_string()))?;

    fun(egraph)
}

pub fn with_egraph_mut<T>(
    resource: &ResourceArc<EGraphResource>,
    fun: impl FnOnce(&mut EGraph) -> Result<T, NativeError>,
) -> Result<T, NativeError> {
    with_mutable_graph(&resource.inner, fun)
}

fn with_mutable_graph<T>(
    inner: &Mutex<Option<EGraph>>,
    fun: impl FnOnce(&mut EGraph) -> Result<T, NativeError>,
) -> Result<T, NativeError> {
    let mut guard = inner.lock().map_err(|_| {
        NativeError::Closed("egraph is unavailable after a native panic".to_string())
    })?;

    let egraph = guard
        .as_mut()
        .ok_or_else(|| NativeError::Closed("egraph is closed".to_string()))?;

    // Catch while holding the guard so unwinding never poisons the mutex.
    // A panicking mutable graph is discarded rather than reused.
    match catch_unwind(AssertUnwindSafe(|| fun(egraph))) {
        Ok(result) => result,
        Err(payload) => {
            guard.take();
            Err(NativeError::Panic(crate::error::panic_payload_to_string(
                payload,
            )))
        }
    }
}

pub fn close_program(program: &ResourceArc<ProgramResource>) -> Result<(), NativeError> {
    let mut guard = program
        .inner
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());

    guard
        .take()
        .map(|_inner| ())
        .ok_or_else(|| NativeError::Closed("program is already closed".to_string()))
}

pub fn close_egraph(egraph: &ResourceArc<EGraphResource>) -> Result<(), NativeError> {
    let mut guard = egraph
        .inner
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());

    guard
        .take()
        .map(|_egraph| ())
        .ok_or_else(|| NativeError::Closed("egraph is already closed".to_string()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cloned_execution_panic_does_not_poison_the_base() {
        let inner = Mutex::new(Some(ProgramInner {
            base: EGraph::default(),
        }));
        let result = with_cloned_base::<()>(&inner, |_| panic!("clone-local test panic"));
        assert!(matches!(result, Err(NativeError::Panic(_))));
        assert!(!inner.is_poisoned());
        assert!(inner.lock().unwrap().is_some());
        assert!(with_cloned_base(&inner, |graph| Ok(graph.num_tuples())).is_ok());
    }

    #[test]
    fn mutable_execution_panic_discards_the_graph_without_poisoning() {
        let inner = Mutex::new(Some(EGraph::default()));
        let result = with_mutable_graph::<()>(&inner, |_| panic!("mutable test panic"));
        assert!(matches!(result, Err(NativeError::Panic(_))));
        assert!(!inner.is_poisoned());
        assert!(inner.lock().unwrap().is_none());
        assert!(matches!(
            with_mutable_graph(&inner, |graph| Ok(graph.num_tuples())),
            Err(NativeError::Closed(_))
        ));
    }
}
