use egglog::ast::{ParseError, Span};
use rustler::{Encoder, Env, NifMap, Term};

use crate::atoms;

/// Positions refer to the source owned by the native span. Byte ranges are
/// zero-based and end-exclusive; line/column positions are one-based.
#[derive(NifMap)]
pub struct SourceLocation {
    file: Option<String>,
    start_byte: usize,
    end_byte: usize,
    start_line: usize,
    start_column: usize,
    end_line: usize,
    end_column: usize,
}

impl SourceLocation {
    fn from_span(span: &Span) -> Option<Self> {
        let Span::Egglog(span) = span else {
            // Internal Rust spans are not positions in user-provided source.
            return None;
        };
        let (start_line, start_column) = span.file.get_location(span.i);
        let (end_line, end_column) = span.file.get_location(span.j);
        Some(Self {
            file: span.file.name.clone(),
            start_byte: span.i,
            end_byte: span.j,
            start_line,
            start_column,
            end_line,
            end_column,
        })
    }
}

pub enum NativeError {
    Parse {
        invalid_theory: bool,
        message: String,
        location: Option<SourceLocation>,
    },
    Closed(String),
    InvalidTheory(String),
    Native(String),
    CheckFailed(String),
    Panic(String),
}

impl NativeError {
    pub fn invalid_theory(error: egglog::Error) -> Self {
        match error {
            egglog::Error::ParseError(error) => Self::parse_error(error, true),
            error => Self::InvalidTheory(error.to_string()),
        }
    }

    fn parse_error(error: ParseError, invalid_theory: bool) -> Self {
        Self::Parse {
            location: SourceLocation::from_span(&error.0),
            message: error.to_string(),
            invalid_theory,
        }
    }

    pub fn encode<'a>(&self, env: Env<'a>) -> Term<'a> {
        match self {
            Self::Parse {
                invalid_theory,
                message,
                location,
            } => {
                let reason = if *invalid_theory {
                    atoms::invalid_theory()
                } else {
                    atoms::native_error()
                };
                (atoms::error(), (reason, message, location)).encode(env)
            }
            Self::Closed(message) => (atoms::error(), atoms::closed(), message).encode(env),
            Self::InvalidTheory(message) => {
                (atoms::error(), atoms::invalid_theory(), message).encode(env)
            }
            Self::CheckFailed(message) => {
                (atoms::error(), atoms::check_failed(), message).encode(env)
            }
            Self::Panic(message) => (atoms::error(), atoms::panic(), message).encode(env),
            Self::Native(message) => (atoms::error(), atoms::native_error(), message).encode(env),
        }
    }
}

impl From<egglog::Error> for NativeError {
    fn from(error: egglog::Error) -> Self {
        let message = error.to_string();
        match error {
            egglog::Error::ParseError(error) => Self::parse_error(error, false),
            egglog::Error::CheckError(..) => Self::CheckFailed(message),
            _ => Self::Native(message),
        }
    }
}

impl From<ParseError> for NativeError {
    fn from(error: ParseError) -> Self {
        Self::parse_error(error, false)
    }
}

impl From<String> for NativeError {
    fn from(message: String) -> Self {
        Self::Native(message)
    }
}

pub fn panic_payload_to_string(payload: Box<dyn std::any::Any + Send>) -> String {
    if let Some(message) = payload.downcast_ref::<&str>() {
        (*message).to_string()
    } else if let Some(message) = payload.downcast_ref::<String>() {
        message.clone()
    } else {
        "native panic".to_string()
    }
}
