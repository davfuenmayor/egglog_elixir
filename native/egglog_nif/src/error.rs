use rustler::{Encoder, Env, Term};

use crate::atoms;

pub enum NativeError {
    Closed(String),
    InvalidTheory(String),
    Native(String),
    CheckFailed(String),
    Panic(String),
}

impl NativeError {
    pub fn encode<'a>(&self, env: Env<'a>) -> Term<'a> {
        match self {
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
            egglog::Error::CheckError(..) => Self::CheckFailed(message),
            _ => Self::Native(message),
        }
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
