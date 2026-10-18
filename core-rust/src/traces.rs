use crate::{gesture::Recognizer, model::Actions, protocol};

pub enum Operation {
    Frame(Vec<u8>),
    Advance,
    Flush,
    Reset,
    Smart(bool),
}
pub struct Step {
    pub scenario: String,
    pub now: f64,
    pub operation: Operation,
}
pub fn unhex(text: &str) -> Result<Vec<u8>, String> {
    let text: String = text.chars().filter(|c| !c.is_whitespace()).collect();
    if !text.is_ascii() || text.len() % 2 != 0 {
        return Err("invalid hex length or alphabet".into());
    }
    (0..text.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&text[i..i + 2], 16).map_err(|e| e.to_string()))
        .collect()
}
pub fn parse(text: &str) -> Result<Vec<Step>, String> {
    text.lines()
        .filter(|s| !s.is_empty() && !s.starts_with('#'))
        .map(|line| {
            let fields: Vec<_> = line.split('\t').collect();
            if fields.len() != 4 {
                return Err(format!("invalid trace: {line}"));
            }
            let operation = match fields[1] {
                "frame" => Operation::Frame(unhex(fields[3])?),
                "advance" => Operation::Advance,
                "flush" => Operation::Flush,
                "reset" => Operation::Reset,
                "smart" if fields[3] == "0" || fields[3] == "1" => {
                    Operation::Smart(fields[3] == "1")
                }
                _ => return Err(format!("unknown operation: {line}")),
            };
            let now: f64 = fields[2].parse::<f64>().map_err(|e| e.to_string())?;
            if !now.is_finite() {
                return Err("nonfinite clock".into());
            }
            Ok(Step {
                scenario: fields[0].into(),
                now,
                operation,
            })
        })
        .collect()
}
pub fn run(core: &mut Recognizer, step: &Step) -> Actions {
    match &step.operation {
        Operation::Frame(bytes) => core.feed(
            &protocol::decode(bytes).expect("valid trace frame"),
            step.now,
        ),
        Operation::Advance => core.advance(step.now),
        Operation::Flush => core.flush(step.now),
        Operation::Reset => core.reset(),
        Operation::Smart(enabled) => {
            core.smart_zoom = *enabled;
            Actions::default()
        }
    }
}
