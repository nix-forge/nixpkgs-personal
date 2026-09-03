use std::fmt::{self, Display, Formatter};

pub(crate) type Result<T> = std::result::Result<T, Error>;

#[derive(Debug)]
pub(crate) struct Error {
    message: String,
    exit_code: u8,
}

impl Error {
    pub(crate) fn usage(message: impl Into<String>) -> Self {
        Self::new(64, message)
    }

    pub(crate) fn unavailable(message: impl Into<String>) -> Self {
        Self::new(69, message)
    }

    pub(crate) fn software(message: impl Into<String>) -> Self {
        Self::new(70, message)
    }

    pub(crate) fn permission(message: impl Into<String>) -> Self {
        Self::new(77, message)
    }

    pub(crate) fn temporary(message: impl Into<String>) -> Self {
        Self::new(75, message)
    }

    pub(crate) const fn exit_code(&self) -> u8 {
        self.exit_code
    }

    fn new(exit_code: u8, message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
            exit_code,
        }
    }
}

impl Display for Error {
    fn fmt(&self, formatter: &mut Formatter<'_>) -> fmt::Result {
        formatter.write_str(&self.message)
    }
}

impl std::error::Error for Error {}
