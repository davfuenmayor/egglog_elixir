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

#[derive(NifMap)]
#[rustler(encode)]
struct DiagnosticLocation {
    location: SourceLocation,
    source: String,
}

#[derive(NifMap)]
#[rustler(encode)]
pub struct Diagnostic {
    category: String,
    locations: Vec<DiagnosticLocation>,
    names: Vec<(String, String)>,
    stage: Option<String>,
    source: Option<String>,
}

impl Diagnostic {
    fn new(category: &str) -> Self {
        Self {
            category: category.to_owned(),
            locations: Vec::new(),
            names: Vec::new(),
            stage: None,
            source: None,
        }
    }
    fn span(&mut self, span: &Span) {
        if let (Span::Egglog(span), Some(location)) = (span, SourceLocation::from_span(span)) {
            self.locations.push(DiagnosticLocation {
                location,
                source: span.file.contents.clone(),
            });
        }
    }
    fn name(&mut self, key: &str, name: &str) {
        self.names.push((key.to_owned(), name.to_owned()));
    }
    fn type_error(&mut self, error: &egglog::TypeError) {
        use egglog::TypeError::*;
        self.category = "type_error".to_owned();
        match error {
            Arity { expr, .. } | Mismatch { expr, .. } | InferenceFailure(expr) => {
                self.span(&expr.span())
            }
            Unbound(name, span)
            | Ungrounded(name, span)
            | UndefinedSort(name, span)
            | UnboundFunction(name, span)
            | ProveExistsRequiresConstructor(name, span)
            | FunctionAlreadyBound(name, span)
            | SortAlreadyBound(name, span)
            | PrimitiveAlreadyBound(name, span)
            | PresortNotFound(name, span)
            | BadPresortArguments(name, span)
            | AlreadyDefined(name, span)
            | ConstructorOutputNotSort(name, span)
            | LookupInRuleDisallowed(name, span)
            | SetConstructorDisallowed(name, span)
            | TermConstructorNoInputs(name, span)
            | NonGlobalPrefixed { name, span }
            | GlobalMissingPrefix { name, span }
            | AmbiguousPrimitive { name, span, .. }
            | UnresolvedPrimitive { name, span, .. } => {
                self.span(span);
                self.name("symbol", name);
            }
            NonEqsortUnion(_, span) | NonUnionableSort(_, span) => self.span(span),
            AllAlternativeFailed(errors) => {
                for error in errors {
                    self.type_error(error);
                }
            }
            FunctionTypeMismatch(..) => {}
        }
    }
}

pub enum NativeError {
    Parse {
        invalid_theory: bool,
        message: String,
        location: Option<SourceLocation>,
    },
    Detailed {
        invalid_theory: bool,
        message: String,
        diagnostic: Diagnostic,
    },
    Closed(String),
    Native(String),
    Panic(String),
}

impl NativeError {
    pub fn invalid_theory(error: egglog::Error) -> Self {
        match error {
            egglog::Error::ParseError(error) => Self::parse_error(error, true),
            error => {
                let mut result = Self::from(error);
                if let Self::Detailed { invalid_theory, .. } = &mut result {
                    *invalid_theory = true;
                }
                result
            }
        }
    }

    fn parse_error(error: ParseError, invalid_theory: bool) -> Self {
        Self::Parse {
            location: SourceLocation::from_span(&error.0),
            message: error.to_string(),
            invalid_theory,
        }
    }

    pub fn context(mut self, stage: &str, source: &str) -> Self {
        if let Self::Detailed { diagnostic, .. } = &mut self {
            if diagnostic.stage.is_none() {
                diagnostic.stage = Some(stage.to_owned());
                diagnostic.source = Some(source.to_owned());
            }
        }
        self
    }

    pub fn stage(mut self, stage: &str) -> Self {
        if let Self::Detailed { diagnostic, .. } = &mut self {
            if diagnostic.stage.is_none() {
                diagnostic.stage = Some(stage.to_owned());
            }
        }
        self
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
            Self::Detailed {
                invalid_theory,
                message,
                diagnostic,
            } => {
                let reason = if *invalid_theory {
                    atoms::invalid_theory()
                } else if diagnostic.category == "check_failed" {
                    atoms::check_failed()
                } else {
                    atoms::native_error()
                };
                (atoms::error(), reason, message, diagnostic).encode(env)
            }
            Self::Closed(message) => (atoms::error(), atoms::closed(), message).encode(env),
            Self::Panic(message) => (atoms::error(), atoms::panic(), message).encode(env),
            Self::Native(message) => (atoms::error(), atoms::native_error(), message).encode(env),
        }
    }
}

impl From<egglog::Error> for NativeError {
    fn from(error: egglog::Error) -> Self {
        use egglog::Error::*;
        if let ParseError(error) = error {
            return Self::parse_error(error, false);
        }
        let message = error.to_string();
        let mut diagnostic = Diagnostic::new("native_error");
        match &error {
            TypeError(error) => diagnostic.type_error(error),
            TypeErrors(errors) => {
                for error in errors {
                    diagnostic.type_error(error);
                }
            }
            CheckError(_, span) => {
                diagnostic.category = "check_failed".into();
                diagnostic.span(span);
            }
            NoSuchRuleset(name, span) | CombinedRulesetError(name, span) => {
                diagnostic.category = "ruleset_error".into();
                diagnostic.name("ruleset", name);
                diagnostic.span(span);
            }
            Pop(span) | ExpectFail(span) => {
                diagnostic.category = if matches!(error, Pop(_)) {
                    "pop"
                } else {
                    "expect_fail"
                }
                .into();
                diagnostic.span(span);
            }
            IoError(path, _, span) => {
                diagnostic.category = "io_error".into();
                diagnostic.name("path", &path.to_string_lossy());
                diagnostic.span(span);
            }
            Shadowing(name, first, second) => {
                diagnostic.category = "shadowing".into();
                diagnostic.name("symbol", name);
                diagnostic.span(first);
                diagnostic.span(second);
            }
            ProofError { span, .. } => {
                diagnostic.category = "proof_error".into();
                diagnostic.span(span);
            }
            SubsumeMergeError(name, span)
            | CommandAlreadyExists(name, span)
            | RuleAlreadyExists(name, span)
            | UnsupportedInputType(name, span) => {
                diagnostic.category = match error {
                    SubsumeMergeError(..) => "subsume_merge",
                    CommandAlreadyExists(..) => "command_exists",
                    RuleAlreadyExists(..) => "rule_exists",
                    _ => "unsupported_input_type",
                }
                .into();
                diagnostic.name("symbol", name);
                diagnostic.span(span);
            }
            DesugarError(span, _) => {
                diagnostic.category = "desugar_error".into();
                diagnostic.span(span);
            }
            NotFoundError(_) => diagnostic.category = "not_found".into(),
            ApiError(_) => diagnostic.category = "api_error".into(),
            BackendError(_) => diagnostic.category = "backend_error".into(),
            ExtractError(_) => diagnostic.category = "extract_error".into(),
            InputFileFormatError(path) => {
                diagnostic.category = "input_format".into();
                diagnostic.name("path", path);
            }
            UnsupportedProofCommand { command, .. } => {
                diagnostic.category = "unsupported_proof_command".into();
                diagnostic.name("command", command);
            }
            ProofsIncompatibleApi { api, .. } => {
                diagnostic.category = "proofs_incompatible_api".into();
                diagnostic.name("api", api);
            }
            ParseError(_) => unreachable!(),
        }
        Self::Detailed {
            invalid_theory: false,
            message,
            diagnostic,
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
