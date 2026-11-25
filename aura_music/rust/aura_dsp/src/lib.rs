// =============================================================================
// lib.rs — Motor DSP nativo en Rust (aura_dsp) para Media3 AudioProcessor
// -----------------------------------------------------------------------------
// Qué hace este archivo:
//   Procesa en tiempo real los buffers PCM entregados por ExoPlayer (Media3)
//   sin asignaciones en el hilo de audio ni bloqueos de mutex entre UI y audio:
//   1. Parámetros atómicos lock-free (habilitado, preamp, limitador, 5 bandas).
//   2. Ecualizador Biquad IIR de 5 bandas en serie por canal (hasta 8 canales):
//      - Banda 0: 60 Hz   (Low-Shelf  - Subgraves)
//      - Banda 1: 230 Hz  (Peaking EQ - Graves)
//      - Banda 2: 910 Hz  (Peaking EQ - Voces)
//      - Banda 3: 3600 Hz (Peaking EQ - Presencia)
//      - Banda 4: 12000 Hz (High-Shelf - Brillo)
//   3. Preamp en dB + Limitador suave (soft-knee tanh) para evitar saturación.
//   4. Soporte para PCM 16-bit signed y PCM 32-bit float mediante DirectByteBuffer.
// =============================================================================

use jni::objects::{JByteBuffer, JClass, JFloatArray};
use jni::sys::{jboolean, jfloat, jint, jstring, JNI_TRUE};
use jni::JNIEnv;
use std::f64::consts::PI;
use std::sync::atomic::{AtomicBool, AtomicI32, AtomicU64, Ordering};
use std::sync::Mutex;

const NUM_BANDS: usize = 5;
const MAX_CHANNELS: usize = 8;

const BAND_FREQS_HZ: [f64; NUM_BANDS] = [60.0, 230.0, 910.0, 3600.0, 12000.0];
const BAND_QS: [f64; NUM_BANDS] = [0.7071, 1.0, 1.0, 1.0, 0.7071];

static DSP_ENABLED: AtomicBool = AtomicBool::new(false);
static LIMITER_ENABLED: AtomicBool = AtomicBool::new(true);
// Almacenados en milidB (ej. +3500 = +3.5 dB) para actualización atómica lock-free
static PREAMP_MILLI_DB: AtomicI32 = AtomicI32::new(0);
static BAND_MILLI_DB: [AtomicI32; NUM_BANDS] = [
    AtomicI32::new(0),
    AtomicI32::new(0),
    AtomicI32::new(0),
    AtomicI32::new(0),
    AtomicI32::new(0),
];
static PARAMS_VERSION: AtomicU64 = AtomicU64::new(1);

static PROCESSOR_STATE: Mutex<Option<DspChain>> = Mutex::new(None);

#[derive(Clone, Copy, Debug)]
struct BiquadCoeffs {
    b0: f64,
    b1: f64,
    b2: f64,
    a1: f64,
    a2: f64,
}

impl Default for BiquadCoeffs {
    fn default() -> Self {
        Self {
            b0: 1.0,
            b1: 0.0,
            b2: 0.0,
            a1: 0.0,
            a2: 0.0,
        }
    }
}

#[derive(Clone, Copy, Debug, Default)]
struct BiquadState {
    z1: f64,
    z2: f64,
}

impl BiquadState {
    #[inline]
    fn process(&mut self, input: f64, c: &BiquadCoeffs) -> f64 {
        let out = c.b0 * input + self.z1;
        self.z1 = c.b1 * input - c.a1 * out + self.z2;
        self.z2 = c.b2 * input - c.a2 * out;
        out
    }

    #[inline]
    fn reset(&mut self) {
        self.z1 = 0.0;
        self.z2 = 0.0;
    }
}

#[derive(Clone, Copy, Debug)]
enum FilterKind {
    LowShelf,
    Peaking,
    HighShelf,
}

fn design_biquad(kind: FilterKind, freq_hz: f64, sample_rate: f64, q: f64, gain_db: f64) -> BiquadCoeffs {
    if gain_db.abs() < 0.01 || sample_rate <= 0.0 {
        return BiquadCoeffs::default();
    }

    // Limitar la frecuencia al 45% de la tasa de muestreo para estabilidad numérica
    let safe_freq = freq_hz.clamp(15.0, sample_rate * 0.45);
    let a = 10.0_f64.powf(gain_db / 40.0);
    let w0 = 2.0 * PI * safe_freq / sample_rate;
    let cos_w0 = w0.cos();
    let sin_w0 = w0.sin();

    let (b0, b1, b2, a0, a1, a2) = match kind {
        FilterKind::LowShelf => {
            let alpha = sin_w0 / 2.0 * ((a + 1.0 / a) * (1.0 / q - 1.0) + 2.0).max(0.01).sqrt();
            let two_sqrt_a_alpha = 2.0 * a.sqrt() * alpha;
            (
                a * ((a + 1.0) - (a - 1.0) * cos_w0 + two_sqrt_a_alpha),
                2.0 * a * ((a - 1.0) - (a + 1.0) * cos_w0),
                a * ((a + 1.0) - (a - 1.0) * cos_w0 - two_sqrt_a_alpha),
                (a + 1.0) + (a - 1.0) * cos_w0 + two_sqrt_a_alpha,
                -2.0 * ((a - 1.0) + (a + 1.0) * cos_w0),
                (a + 1.0) + (a - 1.0) * cos_w0 - two_sqrt_a_alpha,
            )
        }
        FilterKind::Peaking => {
            let alpha = sin_w0 / (2.0 * q.max(0.1));
            (
                1.0 + alpha * a,
                -2.0 * cos_w0,
                1.0 - alpha * a,
                1.0 + alpha / a,
                -2.0 * cos_w0,
                1.0 - alpha / a,
            )
        }
        FilterKind::HighShelf => {
            let alpha = sin_w0 / 2.0 * ((a + 1.0 / a) * (1.0 / q - 1.0) + 2.0).max(0.01).sqrt();
            let two_sqrt_a_alpha = 2.0 * a.sqrt() * alpha;
            (
                a * ((a + 1.0) + (a - 1.0) * cos_w0 + two_sqrt_a_alpha),
                -2.0 * a * ((a - 1.0) + (a + 1.0) * cos_w0),
                a * ((a + 1.0) + (a - 1.0) * cos_w0 - two_sqrt_a_alpha),
                (a + 1.0) - (a - 1.0) * cos_w0 + two_sqrt_a_alpha,
                2.0 * ((a - 1.0) - (a + 1.0) * cos_w0),
                (a + 1.0) - (a - 1.0) * cos_w0 - two_sqrt_a_alpha,
            )
        }
    };

    if a0.abs() < 1e-12 {
        return BiquadCoeffs::default();
    }

    BiquadCoeffs {
        b0: b0 / a0,
        b1: b1 / a0,
        b2: b2 / a0,
        a1: a1 / a0,
        a2: a2 / a0,
    }
}

#[derive(Debug)]
pub struct DspChain {
    sample_rate: u32,
    channels: usize,
    cached_version: u64,
    preamp_linear: f64,
    coeffs: [BiquadCoeffs; NUM_BANDS],
    states: [[BiquadState; NUM_BANDS]; MAX_CHANNELS],
}

impl DspChain {
    pub fn new(sample_rate: u32, channels: usize) -> Self {
        let mut chain = Self {
            sample_rate: sample_rate.max(8000),
            channels: channels.clamp(1, MAX_CHANNELS),
            cached_version: 0,
            preamp_linear: 1.0,
            coeffs: [BiquadCoeffs::default(); NUM_BANDS],
            states: [[BiquadState::default(); NUM_BANDS]; MAX_CHANNELS],
        };
        chain.refresh_coeffs(0, 0.0, &[0.0; NUM_BANDS]);
        chain
    }

    pub fn reset_states(&mut self) {
        for ch in 0..MAX_CHANNELS {
            for b in 0..NUM_BANDS {
                self.states[ch][b].reset();
            }
        }
    }

    pub fn refresh_coeffs(&mut self, version: u64, preamp_db: f64, band_gains_db: &[f64; NUM_BANDS]) {
        let sr = self.sample_rate as f64;
        self.preamp_linear = 10.0_f64.powf(preamp_db.clamp(-12.0, 12.0) / 20.0);
        for band in 0..NUM_BANDS {
            let kind = match band {
                0 => FilterKind::LowShelf,
                4 => FilterKind::HighShelf,
                _ => FilterKind::Peaking,
            };
            self.coeffs[band] = design_biquad(
                kind,
                BAND_FREQS_HZ[band],
                sr,
                BAND_QS[band],
                band_gains_db[band].clamp(-12.0, 12.0),
            );
        }
        self.cached_version = version;
    }

    #[inline]
    fn soft_limit(sample: f64, limiter_on: bool) -> f64 {
        if !limiter_on {
            return sample.clamp(-1.0, 1.0);
        }
        const THRESHOLD: f64 = 0.88;
        let abs = sample.abs();
        if abs <= THRESHOLD {
            return sample;
        }
        let sign = sample.signum();
        let excess = abs - THRESHOLD;
        let headroom = 1.0 - THRESHOLD;
        // Curva suave tanh: evita picos duros y chasquidos digitales sin comprimir la señal normal
        let limited = THRESHOLD + headroom * (excess / headroom).tanh();
        (sign * limited).clamp(-0.998, 0.998)
    }

    pub fn process_sample(&mut self, ch: usize, input: f64, limiter_on: bool) -> f64 {
        let mut x = input * self.preamp_linear;
        let ch_idx = ch.min(MAX_CHANNELS - 1);
        for band in 0..NUM_BANDS {
            x = self.states[ch_idx][band].process(x, &self.coeffs[band]);
        }
        Self::soft_limit(x, limiter_on)
    }

    pub fn process_interleaved_f32(&mut self, samples: &mut [f32], limiter_on: bool) {
        let ch_count = self.channels.max(1);
        for frame in samples.chunks_exact_mut(ch_count) {
            for (ch, s) in frame.iter_mut().enumerate() {
                *s = self.process_sample(ch, *s as f64, limiter_on) as f32;
            }
        }
    }

    pub fn process_interleaved_i16(&mut self, bytes: &mut [u8], limiter_on: bool) {
        let ch_count = self.channels.max(1);
        let frame_bytes = ch_count * 2;
        for frame in bytes.chunks_exact_mut(frame_bytes) {
            for ch in 0..ch_count {
                let off = ch * 2;
                let raw = i16::from_le_bytes([frame[off], frame[off + 1]]);
                let norm = (raw as f64) / 32768.0;
                let out = self.process_sample(ch, norm, limiter_on);
                let scaled = (out * 32767.0).round().clamp(-32768.0, 32767.0) as i16;
                let out_bytes = scaled.to_le_bytes();
                frame[off] = out_bytes[0];
                frame[off + 1] = out_bytes[1];
            }
        }
    }
}

fn read_atomic_params() -> (bool, bool, f64, [f64; NUM_BANDS], u64) {
    let enabled = DSP_ENABLED.load(Ordering::Relaxed);
    let limiter = LIMITER_ENABLED.load(Ordering::Relaxed);
    let preamp_db = (PREAMP_MILLI_DB.load(Ordering::Relaxed) as f64) / 1000.0;
    let mut bands = [0.0_f64; NUM_BANDS];
    for i in 0..NUM_BANDS {
        bands[i] = (BAND_MILLI_DB[i].load(Ordering::Relaxed) as f64) / 1000.0;
    }
    let version = PARAMS_VERSION.load(Ordering::Acquire);
    (enabled, limiter, preamp_db, bands, version)
}

pub fn set_dsp_parameters(
    enabled: bool,
    preamp_db: f32,
    limiter_enabled: bool,
    band_gains_db: &[f32],
) {
    DSP_ENABLED.store(enabled, Ordering::Relaxed);
    LIMITER_ENABLED.store(limiter_enabled, Ordering::Relaxed);
    PREAMP_MILLI_DB.store(
        (preamp_db.clamp(-12.0, 12.0) * 1000.0).round() as i32,
        Ordering::Relaxed,
    );
    for i in 0..NUM_BANDS {
        let gain = band_gains_db.get(i).copied().unwrap_or(0.0).clamp(-12.0, 12.0);
        BAND_MILLI_DB[i].store((gain * 1000.0).round() as i32, Ordering::Relaxed);
    }
    PARAMS_VERSION.fetch_add(1, Ordering::Release);
}

#[no_mangle]
pub extern "system" fn Java_com_auramusic_player_AuraRustDspBridge_nativeEngineInfo(
    mut env: JNIEnv,
    _class: JClass,
) -> jstring {
    let payload = serde_json::json!({
        "rustCrate": "aura_dsp",
        "engine": "Biquad IIR 5-band + Soft Limiter (MIT/Apache-2.0)",
        "arch": std::env::consts::ARCH,
        "bands": NUM_BANDS,
    });
    env.new_string(payload.to_string())
        .map(|s| s.into_raw())
        .unwrap_or(std::ptr::null_mut())
}

#[no_mangle]
pub extern "system" fn Java_com_auramusic_player_AuraRustDspBridge_nativeSetParameters(
    env: JNIEnv,
    _class: JClass,
    enabled: jboolean,
    preamp_db: jfloat,
    limiter_enabled: jboolean,
    band_gains_db: JFloatArray,
) {
    let mut gains = [0.0_f32; NUM_BANDS];
    if !band_gains_db.is_null() {
        let _ = env.get_float_array_region(&band_gains_db, 0, &mut gains);
    }
    set_dsp_parameters(
        enabled == JNI_TRUE,
        preamp_db,
        limiter_enabled == JNI_TRUE,
        &gains,
    );
}

#[no_mangle]
pub extern "system" fn Java_com_auramusic_player_AuraRustDspBridge_nativeResetState(
    _env: JNIEnv,
    _class: JClass,
) {
    if let Ok(mut guard) = PROCESSOR_STATE.lock() {
        if let Some(chain) = guard.as_mut() {
            chain.reset_states();
        }
    }
}

#[no_mangle]
pub extern "system" fn Java_com_auramusic_player_AuraRustDspBridge_nativeProcessPcmBuffer(
    env: JNIEnv,
    _class: JClass,
    buffer: JByteBuffer,
    byte_count: jint,
    sample_rate: jint,
    channel_count: jint,
    is_float: jboolean,
) {
    if byte_count <= 0 || sample_rate <= 0 || channel_count <= 0 {
        return;
    }

    let (enabled, limiter_on, preamp_db, bands, version) = read_atomic_params();
    if !enabled {
        return;
    }

    let ptr = match env.get_direct_buffer_address(&buffer) {
        Ok(p) if !p.is_null() => p,
        _ => return,
    };
    let cap = match env.get_direct_buffer_capacity(&buffer) {
        Ok(c) if c >= byte_count as usize => byte_count as usize,
        _ => return,
    };

    let sr = sample_rate as u32;
    let ch = (channel_count as usize).clamp(1, MAX_CHANNELS);

    let mut guard = match PROCESSOR_STATE.lock() {
        Ok(g) => g,
        Err(poisoned) => poisoned.into_inner(),
    };

    let chain = guard.get_or_insert_with(|| DspChain::new(sr, ch));
    if chain.sample_rate != sr || chain.channels != ch {
        *chain = DspChain::new(sr, ch);
    }
    if chain.cached_version != version {
        chain.refresh_coeffs(version, preamp_db, &bands);
    }

    // SAFETY: DirectByteBuffer validado por JNI con capacidad >= cap y alineado en bloque
    let slice = unsafe { std::slice::from_raw_parts_mut(ptr, cap) };

    if is_float == JNI_TRUE {
        let sample_count = cap / 4;
        if sample_count > 0 && (ptr as usize) % std::mem::align_of::<f32>() == 0 {
            let f32_slice = unsafe {
                std::slice::from_raw_parts_mut(ptr as *mut f32, sample_count)
            };
            chain.process_interleaved_f32(f32_slice, limiter_on);
        }
    } else {
        chain.process_interleaved_i16(slice, limiter_on);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rms(samples: &[f32]) -> f64 {
        let sum: f64 = samples.iter().map(|&s| (s as f64) * (s as f64)).sum();
        (sum / samples.len().max(1) as f64).sqrt()
    }

    fn sine_wave(freq_hz: f64, sample_rate: u32, len: usize) -> Vec<f32> {
        (0..len)
            .map(|i| (2.0 * PI * freq_hz * (i as f64) / (sample_rate as f64)).sin() as f32 * 0.25)
            .collect()
    }

    #[test]
    fn flat_eq_preserves_signal_transparently() {
        let mut chain = DspChain::new(48000, 2);
        chain.refresh_coeffs(1, 0.0, &[0.0; NUM_BANDS]);
        let original = sine_wave(1000.0, 48000, 2000);
        let mut processed = original.clone();
        chain.process_interleaved_f32(&mut processed, true);

        let diff: f32 = original
            .iter()
            .zip(processed.iter())
            .map(|(a, b)| (a - b).abs())
            .fold(0.0, f32::max);
        assert!(diff < 1e-5, "Flat EQ should be transparent, max diff={diff}");
    }

    #[test]
    fn boosting_60hz_increases_low_frequency_energy() {
        let mut chain = DspChain::new(48000, 1);
        chain.refresh_coeffs(2, 0.0, &[9.0, 0.0, 0.0, 0.0, 0.0]);
        let original = sine_wave(55.0, 48000, 4800);
        let mut boosted = original.clone();
        chain.process_interleaved_f32(&mut boosted, true);

        let in_rms = rms(&original[1200..]);
        let out_rms = rms(&boosted[1200..]);
        assert!(out_rms > in_rms * 2.0, "60Hz boost failed: in={in_rms}, out={out_rms}");
    }

    #[test]
    fn soft_limiter_prevents_int16_overflow() {
        let mut chain = DspChain::new(44100, 2);
        chain.refresh_coeffs(3, 12.0, &[12.0, 12.0, 0.0, 0.0, 0.0]);

        let mut pcm_bytes = Vec::with_capacity(4000);
        for i in 0..1000 {
            let sample = ((2.0 * PI * 60.0 * (i as f64) / 44100.0).sin() * 30000.0) as i16;
            pcm_bytes.extend_from_slice(&sample.to_le_bytes());
            pcm_bytes.extend_from_slice(&sample.to_le_bytes());
        }
        chain.process_interleaved_i16(&mut pcm_bytes, true);

        for chunk in pcm_bytes.chunks_exact(2) {
            let val = i16::from_le_bytes([chunk[0], chunk[1]]);
            assert!(val <= 32767 && val >= -32768);
        }
    }

    #[test]
    fn low_sample_rate_high_shelf_does_not_produce_nan() {
        let mut chain = DspChain::new(22050, 2);
        chain.refresh_coeffs(4, 0.0, &[0.0, 0.0, 0.0, 0.0, 8.0]);
        let mut buf = sine_wave(1000.0, 22050, 1024);
        chain.process_interleaved_f32(&mut buf, true);
        assert!(buf.iter().all(|s| s.is_finite()));
    }
}
