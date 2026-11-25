// =============================================================================
// aura_qjs.rs — Runtime JavaScript QuickJS-ng en Rust para yt-dlp-ejs
// -----------------------------------------------------------------------------
// Qué hace este archivo:
//   Compila un ejecutable nativo ligero (empaquetado en Android como
//   jniLibs/<abi>/libaura_qjs.so para 32 y 64 bits) basado en QuickJS-ng a
//   través del crate `rquickjs` (licencia MIT).
//   Implementa exactamente la interfaz CLI esperada por `QuickJsRuntime` y
//   `QuickJSJCP` de `yt-dlp`:
//     - `--help` / `--version`: imprime `QuickJS-ng version 0.12.0 (aura-rust)`
//     - `--script <ruta.js>` (o ruta posicional): evalúa el solver JS de
//       `yt-dlp-ejs` con `console.log` enlazado a stdout y pila ampliada (12 MB)
//       para soportar el parser AST `meriyah` sobre reproductores de YouTube.
// =============================================================================

use rquickjs::{function::Rest, Coerced, Context, Ctx, Error, FromJs, Function, Object, Runtime, Value};
use std::env;
use std::fs;
use std::io::{self, Read};
use std::process::ExitCode;

const VERSION_BANNER: &str = "QuickJS-ng version 0.12.0 (aura-rust)";

fn print_help() {
    println!("{VERSION_BANNER}");
    println!("usage: aura_qjs [options] [file [args]]");
    println!("  -h, --help         show help");
    println!("  -v, --version      show version");
    println!("  -e, --eval EXPR    evaluate EXPR");
    println!("  --script FILE      execute FILE as script");
}

fn format_coerced_args(args: Vec<Coerced<String>>) -> String {
    args.into_iter()
        .map(|c| c.0)
        .collect::<Vec<_>>()
        .join(" ")
}

fn register_console<'js>(ctx: &Ctx<'js>) -> rquickjs::Result<()> {
    let globals = ctx.globals();
    let console = Object::new(ctx.clone())?;

    let log_fn = Function::new(ctx.clone(), |Rest(args): Rest<Coerced<String>>| {
        println!("{}", format_coerced_args(args));
    })?;
    let warn_fn = Function::new(ctx.clone(), |Rest(args): Rest<Coerced<String>>| {
        eprintln!("{}", format_coerced_args(args));
    })?;
    let print_fn = Function::new(ctx.clone(), |Rest(args): Rest<Coerced<String>>| {
        println!("{}", format_coerced_args(args));
    })?;

    console.set("log", log_fn.clone())?;
    console.set("info", log_fn)?;
    console.set("warn", warn_fn.clone())?;
    console.set("error", warn_fn)?;
    globals.set("console", console)?;
    globals.set("print", print_fn)?;
    Ok(())
}

fn execute_js(source: &str) -> Result<(), String> {
    let rt = Runtime::new().map_err(|e| format!("Failed to create QuickJS runtime: {e}"))?;
    // meriyah AST parsing on minified YouTube player.js needs generous stack & memory
    rt.set_max_stack_size(12 * 1024 * 1024);
    rt.set_memory_limit(256 * 1024 * 1024);

    let ctx = Context::full(&rt).map_err(|e| format!("Failed to create QuickJS context: {e}"))?;
    ctx.with(|ctx| {
        register_console(&ctx).map_err(|e| format!("Failed to bind console: {e}"))?;
        match ctx.eval::<Value, _>(source) {
            Ok(_) => Ok(()),
            Err(Error::Exception) => {
                let exc = ctx.catch();
                let msg = Coerced::<String>::from_js(&ctx, exc)
                    .map(|c| c.0)
                    .unwrap_or_else(|_| "Uncaught JS exception".to_string());
                Err(msg)
            }
            Err(err) => Err(format!("JS evaluation error: {err}")),
        }
    })
}

fn run() -> Result<(), String> {
    let args: Vec<String> = env::args().skip(1).collect();
    if args.is_empty() {
        let mut stdin_buf = String::new();
        io::stdin()
            .read_to_string(&mut stdin_buf)
            .map_err(|e| format!("Failed to read stdin: {e}"))?;
        if stdin_buf.trim().is_empty() {
            print_help();
            return Ok(());
        }
        return execute_js(&stdin_buf);
    }

    let mut script_path: Option<String> = None;
    let mut eval_code: Option<String> = None;
    let mut idx = 0;

    while idx < args.len() {
        match args[idx].as_str() {
            "-h" | "--help" | "-v" | "--version" => {
                print_help();
                return Ok(());
            }
            "--script" => {
                idx += 1;
                let path = args
                    .get(idx)
                    .ok_or_else(|| "Missing path after --script".to_string())?;
                script_path = Some(path.clone());
            }
            "-e" | "--eval" => {
                idx += 1;
                let code = args
                    .get(idx)
                    .ok_or_else(|| "Missing expression after -e/--eval".to_string())?;
                eval_code = Some(code.clone());
            }
            "--std" => {
                // Ignored compatibility flag
            }
            other => {
                if !other.starts_with('-') && script_path.is_none() {
                    script_path = Some(other.to_string());
                }
            }
        }
        idx += 1;
    }

    if let Some(code) = eval_code {
        return execute_js(&code);
    }

    if let Some(path) = script_path {
        let source = fs::read_to_string(&path)
            .map_err(|e| format!("Unable to read script '{path}': {e}"))?;
        return execute_js(&source);
    }

    print_help();
    Ok(())
}

fn main() -> ExitCode {
    // Spawn on a 16 MB stack thread so deep recursive AST parsing never hits OS stack limits
    let handle = std::thread::Builder::new()
        .name("aura_qjs_main".to_string())
        .stack_size(16 * 1024 * 1024)
        .spawn(run);

    match handle {
        Ok(join) => match join.join() {
            Ok(Ok(())) => ExitCode::SUCCESS,
            Ok(Err(err)) => {
                eprintln!("{err}");
                ExitCode::from(1)
            }
            Err(_) => {
                eprintln!("aura_qjs panicked during JS execution");
                ExitCode::from(1)
            }
        },
        Err(_) => match run() {
            Ok(()) => ExitCode::SUCCESS,
            Err(err) => {
                eprintln!("{err}");
                ExitCode::from(1)
            }
        },
    }
}
