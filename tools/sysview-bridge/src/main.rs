//! SEGGER SystemView over probe-rs.
//!
//! SystemView talks to the target through RTT, but only J-Link probes are
//! supported natively. This bridge reads the target's "SysView" RTT channel
//! with probe-rs (ST-LINK, CMSIS-DAP, J-Link, ...) and offers it to the
//! SystemView application as an IP recorder (Target > Recorder Configuration >
//! IP, port 19111). One port per core: --target 0:cm7.elf --target 1:cm4.elf
//! listens on 19111 and 19112.
//!
//! probe-rs checks RTT buffers against its memory map of the chip. RAM that
//! map does not list (e.g. the STM32H7 CM4's D2 SRAM alias at 0x10000000) is
//! added with --ram START:SIZE.
//!
//! --record captures a fixed time span without the SystemView application and
//! prints the strings found in the stream (system description, task and module
//! names), which is enough to check an image on a headless machine.

use std::fs;
use std::io::{ErrorKind, Read, Write};
use std::net::{TcpListener, TcpStream};
use std::path::{Path, PathBuf};
use std::thread;
use std::time::{Duration, Instant};

use anyhow::{Context, Result, anyhow, bail};
use clap::Parser;
use object::{Object, ObjectSymbol};
use probe_rs::config::{MemoryRegion, RamRegion, Registry};
use probe_rs::probe::DebugProbeSelector;
use probe_rs::probe::list::Lister;
use probe_rs::rtt::{Rtt, ScanRegion};
use probe_rs::{Permissions, Session};

/// RTT channel name used by SEGGER_SYSVIEW_Init().
const SYSVIEW_CHANNEL_NAME: &str = "SysView";
/// Host commands (SEGGER_SYSVIEW_Int.h).
const COMMAND_START: u8 = 1;
const COMMAND_STOP: u8 = 2;
/// IP recorder handshake: both sides send a 32-byte hello first.
const HELLO_SIZE: usize = 32;
const TARGET_HELLO: &[u8] = b"SEGGER SystemView V3.32.00";

#[derive(Parser)]
#[command(version, about)]
struct Args {
    /// probe-rs chip name, e.g. STM32H755ZITx.
    #[arg(long)]
    chip: String,

    /// Probe selector VID:PID[:SERIAL]; default: the only connected probe.
    #[arg(long)]
    probe: Option<DebugProbeSelector>,

    /// <core index>:<ELF file or RTT control block address>, repeatable.
    /// The ELF file is searched for _SEGGER_RTT.
    #[arg(long = "target", required = true, value_name = "CORE:ELF|ADDR")]
    targets: Vec<String>,

    /// Extra RAM region START:SIZE (hex or decimal) for all cores, repeatable.
    /// For RAM missing from probe-rs' memory map of the chip, e.g. the
    /// STM32H755 CM4's D2 SRAM alias: --ram 0x10000000:0x48000.
    #[arg(long = "ram", value_name = "START:SIZE")]
    extra_ram: Vec<String>,

    /// TCP port of the first target; the next targets use the following ports.
    #[arg(long, default_value_t = 19111)]
    port: u16,

    /// Record into this directory instead of serving SystemView
    /// (<dir>/core<N>.bin, the raw SystemView stream).
    #[arg(long, value_name = "DIR")]
    record: Option<PathBuf>,

    /// Recording length in seconds (with --record).
    #[arg(long, default_value_t = 5.0)]
    duration: f64,
}

/// One core's SystemView channel.
struct Target {
    core_index: usize,
    rtt: Rtt,
    channel: usize,
}

impl Target {
    fn attach(session: &mut Session, spec: &str) -> Result<Self> {
        let (core_text, location) = spec
            .split_once(':')
            .ok_or_else(|| anyhow!("--target {spec}: expected CORE:ELF or CORE:ADDR"))?;
        let core_index: usize = core_text
            .parse()
            .with_context(|| format!("--target {spec}: bad core index"))?;
        let region = match parse_address(location) {
            Some(address) => ScanRegion::Exact(address),
            None => ScanRegion::Exact(rtt_address_from_elf(Path::new(location))?),
        };

        let mut core = session.core(core_index)?;
        let mut rtt = Rtt::attach_region(&mut core, &region).with_context(|| {
            format!("core {core_index}: no RTT control block (is the image running and SEGGER_SYSVIEW_Conf() called?)")
        })?;
        let channel = rtt
            .up_channels()
            .iter()
            .find(|channel| channel.name() == Some(SYSVIEW_CHANNEL_NAME))
            .map(|channel| channel.number())
            .ok_or_else(|| anyhow!("core {core_index}: no \"{SYSVIEW_CHANNEL_NAME}\" RTT up channel"))?;
        if rtt.down_channel(channel).is_none() {
            bail!("core {core_index}: no RTT down channel {channel} for SystemView commands");
        }
        Ok(Self { core_index, rtt, channel })
    }

    fn read(&mut self, session: &mut Session, buf: &mut [u8]) -> Result<usize> {
        let mut core = session.core(self.core_index)?;
        let channel = self.rtt.up_channel(self.channel).expect("checked in attach()");
        Ok(channel.read(&mut core, buf)?)
    }

    fn write_all(&mut self, session: &mut Session, mut data: &[u8]) -> Result<()> {
        let mut core = session.core(self.core_index)?;
        let channel = self.rtt.down_channel(self.channel).expect("checked in attach()");
        let deadline = Instant::now() + Duration::from_secs(1);
        while !data.is_empty() {
            let written = channel.write(&mut core, data)?;
            data = &data[written..];
            if written == 0 {
                if Instant::now() > deadline {
                    bail!("core {}: target does not drain the SystemView down channel", self.core_index);
                }
                thread::sleep(Duration::from_millis(1));
            }
        }
        Ok(())
    }

    /// Discards data left over from an earlier session.
    fn drain(&mut self, session: &mut Session) -> Result<()> {
        let mut buf = [0u8; 4096];
        while self.read(session, &mut buf)? > 0 {}
        Ok(())
    }
}

fn parse_address(text: &str) -> Option<u64> {
    let hex = text.strip_prefix("0x").or_else(|| text.strip_prefix("0X"))?;
    u64::from_str_radix(hex, 16).ok()
}

fn parse_number(text: &str) -> Option<u64> {
    parse_address(text).or_else(|| text.parse().ok())
}

fn parse_ram(spec: &str) -> Result<std::ops::Range<u64>> {
    let (start, size) = spec
        .split_once(':')
        .and_then(|(start, size)| Some((parse_number(start)?, parse_number(size)?)))
        .ok_or_else(|| anyhow!("--ram {spec}: expected START:SIZE"))?;
    Ok(start..start + size)
}

fn rtt_address_from_elf(path: &Path) -> Result<u64> {
    let data = fs::read(path).with_context(|| format!("cannot read {}", path.display()))?;
    let file = object::File::parse(&*data).with_context(|| format!("{} is not an object file", path.display()))?;
    file.symbols()
        .find(|symbol| symbol.name() == Ok("_SEGGER_RTT"))
        .map(|symbol| symbol.address())
        .ok_or_else(|| anyhow!("{}: no _SEGGER_RTT symbol", path.display()))
}

fn open_session(args: &Args) -> Result<Session> {
    let lister = Lister::new();
    let probe = match &args.probe {
        Some(selector) => lister.open(selector.clone())?,
        None => {
            let probes = lister.list_all();
            match probes.as_slice() {
                [only] => only.open()?,
                [] => bail!("no debug probe found"),
                _ => bail!("{} probes found, select one with --probe VID:PID[:SERIAL]", probes.len()),
            }
        }
    };
    let registry = Registry::from_builtin_families();
    let mut target = registry.get_target_by_name(&args.chip)?;
    let cores: Vec<String> = target.cores.iter().map(|core| core.name.clone()).collect();
    for spec in &args.extra_ram {
        target.memory_map.push(MemoryRegion::Ram(RamRegion {
            name: Some(format!("--ram {spec}")),
            range: parse_ram(spec)?,
            cores: cores.clone(),
            is_alias: false,
            access: None,
        }));
    }
    // Plain attach: no reset, no halt; the images keep running.
    Ok(probe.attach(target, Permissions::default())?)
}

fn main() -> Result<()> {
    let args = Args::parse();
    let mut session = open_session(&args)?;
    let mut targets = args
        .targets
        .iter()
        .map(|spec| Target::attach(&mut session, spec))
        .collect::<Result<Vec<_>>>()?;
    for target in &targets {
        println!("core {}: SystemView on RTT channel {}", target.core_index, target.channel);
    }

    match &args.record {
        Some(dir) => record(&mut session, &mut targets, dir, Duration::from_secs_f64(args.duration)),
        None => serve(&mut session, &mut targets, args.port),
    }
}

// --- IP recorder bridge -----------------------------------------------------

struct Connection {
    stream: TcpStream,
}

fn serve(session: &mut Session, targets: &mut [Target], first_port: u16) -> Result<()> {
    let mut listeners = Vec::new();
    for (offset, target) in targets.iter().enumerate() {
        let port = first_port + u16::try_from(offset)?;
        let listener = TcpListener::bind(("127.0.0.1", port)).with_context(|| format!("cannot listen on port {port}"))?;
        listener.set_nonblocking(true)?;
        println!("core {}: SystemView IP recorder at 127.0.0.1:{port}", target.core_index);
        listeners.push(listener);
    }

    let mut connections: Vec<Option<Connection>> = targets.iter().map(|_| None).collect();
    let mut buf = [0u8; 4096];
    loop {
        let mut busy = false;
        for (index, target) in targets.iter_mut().enumerate() {
            if connections[index].is_none() {
                if let Some(connection) = accept(&listeners[index], session, target)? {
                    connections[index] = Some(connection);
                }
                continue;
            }
            let connection = connections[index].as_mut().expect("checked above");
            match relay(session, target, connection, &mut buf) {
                Ok(moved) => busy |= moved,
                Err(error) => {
                    println!("core {}: SystemView disconnected ({error:#})", target.core_index);
                    // Stop the recording so the target does not keep filling
                    // its buffer for nobody.
                    target.write_all(session, &[COMMAND_STOP])?;
                    connections[index] = None;
                }
            }
        }
        if !busy {
            thread::sleep(Duration::from_millis(1));
        }
    }
}

fn accept(listener: &TcpListener, session: &mut Session, target: &mut Target) -> Result<Option<Connection>> {
    let mut stream = match listener.accept() {
        Ok((stream, _)) => stream,
        Err(error) if error.kind() == ErrorKind::WouldBlock => return Ok(None),
        Err(error) => return Err(error.into()),
    };
    stream.set_nonblocking(false)?;
    stream.set_read_timeout(Some(Duration::from_secs(2)))?;
    let mut hello = [0u8; HELLO_SIZE];
    if let Err(error) = stream.read_exact(&mut hello) {
        println!("core {}: no hello from SystemView ({error})", target.core_index);
        return Ok(None);
    }
    let mut reply = [0u8; HELLO_SIZE];
    reply[..TARGET_HELLO.len()].copy_from_slice(TARGET_HELLO);
    stream.write_all(&reply)?;
    stream.set_nonblocking(true)?;
    stream.set_nodelay(true)?;
    target.drain(session)?;
    println!("core {}: SystemView connected", target.core_index);
    Ok(Some(Connection { stream }))
}

/// Moves pending data in both directions; returns whether anything moved.
fn relay(session: &mut Session, target: &mut Target, connection: &mut Connection, buf: &mut [u8]) -> Result<bool> {
    let mut moved = false;
    match connection.stream.read(buf) {
        Ok(0) => bail!("connection closed"),
        Ok(count) => {
            target.write_all(session, &buf[..count])?;
            moved = true;
        }
        Err(error) if error.kind() == ErrorKind::WouldBlock => {}
        Err(error) => return Err(error.into()),
    }
    let count = target.read(session, buf)?;
    if count > 0 {
        connection.stream.set_nonblocking(false)?;
        let result = connection.stream.write_all(&buf[..count]);
        connection.stream.set_nonblocking(true)?;
        result?;
        moved = true;
    }
    Ok(moved)
}

// --- Headless recording -----------------------------------------------------

fn record(session: &mut Session, targets: &mut [Target], dir: &Path, duration: Duration) -> Result<()> {
    fs::create_dir_all(dir)?;
    let mut streams: Vec<Vec<u8>> = targets.iter().map(|_| Vec::new()).collect();
    for target in targets.iter_mut() {
        target.drain(session)?;
        target.write_all(session, &[COMMAND_START])?;
    }

    let mut buf = [0u8; 4096];
    let start = Instant::now();
    let mut stopped = false;
    // Keep reading for a moment after STOP to collect the tail.
    while start.elapsed() < duration + Duration::from_millis(200) {
        if !stopped && start.elapsed() >= duration {
            for target in targets.iter_mut() {
                target.write_all(session, &[COMMAND_STOP])?;
            }
            stopped = true;
        }
        let mut busy = false;
        for (target, stream) in targets.iter_mut().zip(streams.iter_mut()) {
            let count = target.read(session, &mut buf)?;
            stream.extend_from_slice(&buf[..count]);
            busy |= count > 0;
        }
        if !busy {
            thread::sleep(Duration::from_millis(1));
        }
    }

    for (target, stream) in targets.iter().zip(streams.iter()) {
        let path = dir.join(format!("core{}.bin", target.core_index));
        fs::write(&path, stream)?;
        println!(
            "core {}: {} bytes in {:.1} s ({:.1} KiB/s) -> {}",
            target.core_index,
            stream.len(),
            duration.as_secs_f64(),
            stream.len() as f64 / 1024.0 / duration.as_secs_f64(),
            path.display()
        );
        println!("  strings: {}", strings(stream, 4).join(" | "));
    }
    Ok(())
}

/// Printable ASCII runs of at least `min_len` bytes, deduplicated.
fn strings(data: &[u8], min_len: usize) -> Vec<String> {
    let mut found: Vec<String> = Vec::new();
    for run in data.split(|byte| !(0x20..0x7f).contains(byte)) {
        if run.len() >= min_len {
            let text = String::from_utf8_lossy(run).into_owned();
            if !found.contains(&text) {
                found.push(text);
            }
        }
    }
    found
}
