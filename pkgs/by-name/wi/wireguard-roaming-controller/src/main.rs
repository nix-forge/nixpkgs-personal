#![forbid(unsafe_code)]

mod command;
mod config;
mod controller;
mod dns;
mod error;
mod policy;
mod state;
mod system;

use std::process::ExitCode;

use config::{Config, USAGE};
use controller::Controller;
use system::MacosSystem;

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("wireguard-roaming: {error}");
            if error.exit_code() == 64 && error.to_string() != USAGE {
                eprintln!("{USAGE}");
            }
            ExitCode::from(error.exit_code())
        }
    }
}

fn run() -> error::Result<()> {
    let config = Config::parse(std::env::args_os())?;
    let action = config.action;
    let system = MacosSystem::new(config.clone());
    let mut controller = Controller::new(config, system);
    controller.execute(action)
}
