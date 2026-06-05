use std::sync::Mutex;

use egglog::{EGraph, ast::Command};
use rustler::{Resource, ResourceArc};

use crate::error::NativeError;

pub struct ProgramInner {
    pub base: EGraph,
}

pub struct ProgramResource {
    // Per-resource guard only. This is not a process-wide scheduler lock:
    // it protects the lifetime of this loaded base and serializes query-local
    // clone/run work for this one handle.
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
    fun: impl FnOnce(&mut EGraph) -> Result<T, String>,
) -> Result<T, NativeError> {
    let guard = program
        .inner
        .lock()
        .map_err(|_| NativeError::Native("program mutex poisoned".to_string()))?;

    let inner = guard
        .as_ref()
        .ok_or_else(|| NativeError::Closed("program is closed".to_string()))?;

    let mut egraph = inner.base.clone();
    fun(&mut egraph).map_err(NativeError::Native)
}

pub fn with_program<T>(
    program: &ResourceArc<ProgramResource>,
    fun: impl FnOnce(&ProgramInner) -> Result<T, String>,
) -> Result<T, NativeError> {
    let guard = program
        .inner
        .lock()
        .map_err(|_| NativeError::Native("program mutex poisoned".to_string()))?;

    let inner = guard
        .as_ref()
        .ok_or_else(|| NativeError::Closed("program is closed".to_string()))?;

    fun(inner).map_err(NativeError::Native)
}

pub fn with_egraph<T>(
    resource: &ResourceArc<EGraphResource>,
    fun: impl FnOnce(&EGraph) -> Result<T, String>,
) -> Result<T, NativeError> {
    let guard = resource
        .inner
        .lock()
        .map_err(|_| NativeError::Native("egraph mutex poisoned".to_string()))?;

    let egraph = guard
        .as_ref()
        .ok_or_else(|| NativeError::Closed("egraph is closed".to_string()))?;

    fun(egraph).map_err(NativeError::Native)
}

pub fn with_egraph_mut<T>(
    resource: &ResourceArc<EGraphResource>,
    fun: impl FnOnce(&mut EGraph) -> Result<T, String>,
) -> Result<T, NativeError> {
    let mut guard = resource
        .inner
        .lock()
        .map_err(|_| NativeError::Native("egraph mutex poisoned".to_string()))?;

    let egraph = guard
        .as_mut()
        .ok_or_else(|| NativeError::Closed("egraph is closed".to_string()))?;

    fun(egraph).map_err(NativeError::Native)
}

pub fn close_program(program: &ResourceArc<ProgramResource>) -> Result<(), NativeError> {
    let mut guard = program
        .inner
        .lock()
        .map_err(|_| NativeError::Native("program mutex poisoned".to_string()))?;

    guard
        .take()
        .map(|_inner| ())
        .ok_or_else(|| NativeError::Closed("program is already closed".to_string()))
}

pub fn close_egraph(egraph: &ResourceArc<EGraphResource>) -> Result<(), NativeError> {
    let mut guard = egraph
        .inner
        .lock()
        .map_err(|_| NativeError::Native("egraph mutex poisoned".to_string()))?;

    guard
        .take()
        .map(|_egraph| ())
        .ok_or_else(|| NativeError::Closed("egraph is already closed".to_string()))
}
