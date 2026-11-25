// =============================================================================
// lib.rs — Motor DSP nativo en Rust (aura_dsp) para Media3 AudioProcessor
// -----------------------------------------------------------------------------
// Qué hace este archivo:
//   Procesa en tiempo real los buffers PCM entregados por ExoPlayer (Media3)
//   sin asignaciones en el hilo de audio ni bloqueos de mutex entre UI y audio:
//   1. Parámetros atómicos lock-free (EQ habilitado, preamp, limitador, 5 bandas
//      y módulo de Audio 8D orbital sin reverb).
//   2. Ecualizador Biquad IIR de 5 bandas en serie por canal (hasta 8 canales):
//      - Banda 0: 60 Hz   (Low-Shelf  - Subgraves)
//      - Banda 1: 230 Hz  (Peaking EQ - Graves)
//      - Banda 2: 910 Hz  (Peaking EQ - Voces)
//      - Banda 3: 3600 Hz (Peaking EQ - Presencia)
//      - Banda 4: 12000 Hz (High-Shelf - Brillo)
//   3. Procesador Audio 8D orbital (sin reverb):
//      - Modo Auriculares (output_mode = 0): paneo orbital constante,
//        micro-retardo interaural ITD con interpolación lineal y filtro de
//        sombra craneal / frente-atrás por oído.
//      - Modo Altavoz (output_mode = 1): seguro para mono y altavoces cercanos
//        (sin ITD destructivo), anchura Mid/Side controlada y contorno orbital
//        de presencia frente-atrás sin cancelación de fase.
//   4. Preamp en dB + Limitador suave (soft-knee tanh) para evitar saturación.
//   5. Soporte para PCM 16-bit signed y PCM 32-bit float mediante DirectByteBuffer.
// =============================================================================

use jni::objects::{JByteBuffer, JClass, JFloatArray};
use jni::sys::{jboolean, jfloat, jint, jstring, JNI_TRUE};
use jni::JNIEnv;
use std::f64::consts::{PI, SQRT_2};
use std::sync::atomic::{AtomicBool, AtomicI32, AtomicU64, Ordering};
use std::sync::Mutex;

const NUM_BANDS: usize = 5;
const MAX_CHANNELS: usize = 8;
const ITD_RING_SIZE: usize = 128;
const ITD_RING_MASK: usize = ITD_RING_SIZE - 1;

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

// Parámetros atómicos lock-free del procesador Audio 8D (sin reverb)
static SPATIAL_8D_ENABLED: AtomicBool = AtomicBool::new(false);
// 0 = Auriculares (binaural completo), 1 = Altavoz (mono-safe sin cancelación)
static SPATIAL_8D_OUTPUT_MODE: AtomicI32 = AtomicI32::new(1);
// Frecuencia de órbita en mili-Hz (ej. 160 = 0.16 Hz ≈ 6.25 s por vuelta)
static SPATIAL_8D_SPEED_MILLI_HZ: AtomicI32 = AtomicI32::new(160);
// Intensidad de efecto en porcentaje 0..100
static SPATIAL_8D_INTENSITY_PERCENT: AtomicI32 = AtomicI32::new(75);

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

fn design_biquad(
    kind: FilterKind,
    freq_hz: f64,
    sample_rate: f64,
    q: f64,
    gain_db: f64,
) -> BiquadCoeffs {
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

#[derive(Clone, Copy, Debug)]
pub struct Spatial8dParams {
    pub enabled: bool,
    /// 0 = Auriculares (binaural), 1 = Altavoz (mono-safe)
    pub output_mode: i32,
    /// Velocidad orbital en Hz (0.05..=0.50)
    pub speed_hz: f64,
    /// Intensidad (0.0..=1.0)
    pub intensity: f64,
}

impl Default for Spatial8dParams {
    fn default() -> Self {
        Self {
            enabled: false,
            output_mode: 1,
            speed_hz: 0.16,
            intensity: 0.75,
        }
    }
}

#[derive(Debug)]
struct Spatial8dProcessor {
    orbit_phase: f64,
    itd_ring: [[f64; ITD_RING_SIZE]; 2],
    itd_write_idx: usize,
    shadow_lp_state: [f64; 2],
    speaker_split_lp: [f64; 2],
}

impl Default for Spatial8dProcessor {
    fn default() -> Self {
        Self {
            orbit_phase: 0.0,
            itd_ring: [[0.0; ITD_RING_SIZE]; 2],
            itd_write_idx: 0,
            shadow_lp_state: [0.0; 2],
            speaker_split_lp: [0.0; 2],
        }
    }
}

impl Spatial8dProcessor {
    fn reset(&mut self) {
        self.itd_ring = [[0.0; ITD_RING_SIZE]; 2];
        self.itd_write_idx = 0;
        self.shadow_lp_state = [0.0; 2];
        self.speaker_split_lp = [0.0; 2];
    }

    #[inline]
    fn read_delayed(&self, ch: usize, delay_samples: f64) -> f64 {
        let clamped_delay = delay_samples.clamp(0.0, (ITD_RING_SIZE - 4) as f64);
        let int_delay = clamped_delay.floor() as usize;
        let frac = clamped_delay - (int_delay as f64);
        let idx0 = (self.itd_write_idx + ITD_RING_SIZE - int_delay) & ITD_RING_MASK;
        let idx1 = (idx0 + ITD_RING_SIZE - 1) & ITD_RING_MASK;
        let s0 = self.itd_ring[ch][idx0];
        let s1 = self.itd_ring[ch][idx1];
        s0 + frac * (s1 - s0)
    }

    #[inline]
    fn one_pole_alpha(cutoff_hz: f64, sample_rate: f64) -> f64 {
        let safe_cut = cutoff_hz.clamp(80.0, sample_rate * 0.45);
        1.0 - (-2.0 * PI * safe_cut / sample_rate).exp()
    }

    #[inline]
    fn process_stereo_frame(
        &mut self,
        left_in: f64,
        right_in: f64,
        sample_rate: f64,
        params: &Spatial8dParams,
    ) -> (f64, f64) {
        let sr = sample_rate.max(8000.0);
        let mix = params.intensity.clamp(0.0, 1.0);
        let angle = 2.0 * PI * self.orbit_phase;
        let pan = angle.sin(); // -1.0 = izquierda, +1.0 = derecha
        let front_back = angle.cos(); // +1.0 = frente, -1.0 = detrás

        let (out_l, out_r) = if params.output_mode == 0 {
            // -----------------------------------------------------------------
            // Modo Auriculares (8D Binaural sin reverb):
            //   1. Crossfeed sutil para no perder instrumentos paneados al girar
            //   2. Paneo orbital de potencia constante
            //   3. Micro-retardo interaural (ITD) hasta 0.45 ms
            //   4. Filtro pasa-bajos de sombra craneal + calidez trasera
            // -----------------------------------------------------------------
            let cross = 0.14 * mix;
            let l_src = left_in * (1.0 - cross) + right_in * cross;
            let r_src = right_in * (1.0 - cross) + left_in * cross;

            let theta = (pan * 0.80 * mix + 1.0) * (PI / 4.0);
            let gain_l = theta.cos() * SQRT_2;
            let gain_r = theta.sin() * SQRT_2;

            let l_pan = l_src * gain_l;
            let r_pan = r_src * gain_r;

            let w = self.itd_write_idx;
            self.itd_ring[0][w] = l_pan;
            self.itd_ring[1][w] = r_pan;

            let max_delay_samples = (0.00045 * sr * mix).min((ITD_RING_SIZE - 4) as f64);
            let delay_l = if pan > 0.0 { pan * max_delay_samples } else { 0.0 };
            let delay_r = if pan < 0.0 { (-pan) * max_delay_samples } else { 0.0 };

            let l_del = self.read_delayed(0, delay_l);
            let r_del = self.read_delayed(1, delay_r);
            self.itd_write_idx = (w + 1) & ITD_RING_MASK;

            let back_factor = (-front_back).max(0.0) * mix;
            let far_l = pan.max(0.0) * mix;
            let far_r = (-pan).max(0.0) * mix;

            let cutoff_l = (19500.0 - far_l * 14500.0 - back_factor * 4500.0).clamp(3200.0, 19500.0);
            let cutoff_r = (19500.0 - far_r * 14500.0 - back_factor * 4500.0).clamp(3200.0, 19500.0);

            let alpha_l = Self::one_pole_alpha(cutoff_l, sr);
            let alpha_r = Self::one_pole_alpha(cutoff_r, sr);

            self.shadow_lp_state[0] += alpha_l * (l_del - self.shadow_lp_state[0]);
            self.shadow_lp_state[1] += alpha_r * (r_del - self.shadow_lp_state[1]);

            (self.shadow_lp_state[0], self.shadow_lp_state[1])
        } else {
            // -----------------------------------------------------------------
            // Modo Altavoz (Mono-safe sin reverb ni cancelación de fase):
            //   - Sin ITD para no producir comb-filtering al sumarse en mono
            //   - Anchura Mid/Side controlada + paneo suave para altavoces estéreo
            //   - Contorno espectral frente-atrás (~2.1 kHz) audible incluso en
            //     teléfonos de un solo altavoz sin alterar el volumen medio
            // -----------------------------------------------------------------
            let mid = 0.5 * (left_in + right_in);
            let side = 0.5 * (left_in - right_in);
            let side_gain = 1.0 + 0.45 * mix;
            let l_wide = mid + side * side_gain;
            let r_wide = mid - side * side_gain;

            let theta = (pan * 0.22 * mix + 1.0) * (PI / 4.0);
            let l_pan = l_wide * theta.cos() * SQRT_2;
            let r_pan = r_wide * theta.sin() * SQRT_2;

            let split_alpha = Self::one_pole_alpha(2100.0, sr);
            self.speaker_split_lp[0] += split_alpha * (l_pan - self.speaker_split_lp[0]);
            self.speaker_split_lp[1] += split_alpha * (r_pan - self.speaker_split_lp[1]);

            let high_l = l_pan - self.speaker_split_lp[0];
            let high_r = r_pan - self.speaker_split_lp[1];
            let high_scale = 1.0 + 0.24 * mix * front_back;

            (
                self.speaker_split_lp[0] + high_l * high_scale,
                self.speaker_split_lp[1] + high_r * high_scale,
            )
        };

        self.advance_phase(sr, params.speed_hz);
        (out_l, out_r)
    }

    #[inline]
    fn process_mono_sample(
        &mut self,
        input: f64,
        sample_rate: f64,
        params: &Spatial8dParams,
    ) -> f64 {
        let sr = sample_rate.max(8000.0);
        let mix = params.intensity.clamp(0.0, 1.0);
        let front_back = (2.0 * PI * self.orbit_phase).cos();
        let split_alpha = Self::one_pole_alpha(2100.0, sr);
        self.speaker_split_lp[0] += split_alpha * (input - self.speaker_split_lp[0]);
        let high = input - self.speaker_split_lp[0];
        let high_scale = 1.0 + 0.24 * mix * front_back;
        self.advance_phase(sr, params.speed_hz);
        self.speaker_split_lp[0] + high * high_scale
    }

    #[inline]
    fn advance_phase(&mut self, sample_rate: f64, speed_hz: f64) {
        let step = speed_hz.clamp(0.05, 0.50) / sample_rate.max(8000.0);
        self.orbit_phase += step;
        if self.orbit_phase >= 1.0 {
            self.orbit_phase -= 1.0;
        }
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
    spatial: Spatial8dProcessor,
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
            spatial: Spatial8dProcessor::default(),
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
        self.spatial.reset();
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

    #[inline]
    fn process_eq_sample(&mut self, ch: usize, input: f64) -> f64 {
        let mut x = input * self.preamp_linear;
        let ch_idx = ch.min(MAX_CHANNELS - 1);
        for band in 0..NUM_BANDS {
            x = self.states[ch_idx][band].process(x, &self.coeffs[band]);
        }
        x
    }

    pub fn process_sample(&mut self, ch: usize, input: f64, limiter_on: bool) -> f64 {
        let x = self.process_eq_sample(ch, input);
        Self::soft_limit(x, limiter_on)
    }

    #[inline]
    fn process_frame_buf(
        &mut self,
        frame_buf: &mut [f64; MAX_CHANNELS],
        ch_count: usize,
        eq_on: bool,
        limiter_on: bool,
        spatial: &Spatial8dParams,
    ) {
        if eq_on {
            for (ch, s) in frame_buf[..ch_count].iter_mut().enumerate() {
                *s = self.process_eq_sample(ch, *s);
            }
        }

        if spatial.enabled {
            let sr = self.sample_rate as f64;
            if ch_count >= 2 {
                let (l, r) = self.spatial.process_stereo_frame(
                    frame_buf[0],
                    frame_buf[1],
                    sr,
                    spatial,
                );
                frame_buf[0] = l;
                frame_buf[1] = r;
            } else if ch_count == 1 {
                frame_buf[0] = self.spatial.process_mono_sample(frame_buf[0], sr, spatial);
            }
        }

        let apply_limiter = limiter_on || spatial.enabled;
        for s in frame_buf[..ch_count].iter_mut() {
            *s = Self::soft_limit(*s, apply_limiter);
        }
    }

    pub fn process_interleaved_f32(&mut self, samples: &mut [f32], limiter_on: bool) {
        self.process_interleaved_f32_full(
            samples,
            true,
            limiter_on,
            &Spatial8dParams::default(),
        );
    }

    pub fn process_interleaved_f32_full(
        &mut self,
        samples: &mut [f32],
        eq_on: bool,
        limiter_on: bool,
        spatial: &Spatial8dParams,
    ) {
        let ch_count = self.channels.clamp(1, MAX_CHANNELS);
        let mut frame_buf = [0.0_f64; MAX_CHANNELS];
        for frame in samples.chunks_exact_mut(ch_count) {
            for (ch, s) in frame.iter().enumerate() {
                frame_buf[ch] = *s as f64;
            }
            self.process_frame_buf(&mut frame_buf, ch_count, eq_on, limiter_on, spatial);
            for (ch, s) in frame.iter_mut().enumerate() {
                *s = frame_buf[ch] as f32;
            }
        }
    }

    pub fn process_interleaved_i16(&mut self, bytes: &mut [u8], limiter_on: bool) {
        self.process_interleaved_i16_full(
            bytes,
            true,
            limiter_on,
            &Spatial8dParams::default(),
        );
    }

    pub fn process_interleaved_i16_full(
        &mut self,
        bytes: &mut [u8],
        eq_on: bool,
        limiter_on: bool,
        spatial: &Spatial8dParams,
    ) {
        let ch_count = self.channels.clamp(1, MAX_CHANNELS);
        let frame_bytes = ch_count * 2;
        let mut frame_buf = [0.0_f64; MAX_CHANNELS];
        for frame in bytes.chunks_exact_mut(frame_bytes) {
            for ch in 0..ch_count {
                let off = ch * 2;
                let raw = i16::from_le_bytes([frame[off], frame[off + 1]]);
                frame_buf[ch] = (raw as f64) / 32768.0;
            }
            self.process_frame_buf(&mut frame_buf, ch_count, eq_on, limiter_on, spatial);
            for ch in 0..ch_count {
                let off = ch * 2;
                let scaled = (frame_buf[ch] * 32767.0).round().clamp(-32768.0, 32767.0) as i16;
                let out_bytes = scaled.to_le_bytes();
                frame[off] = out_bytes[0];
                frame[off + 1] = out_bytes[1];
            }
        }
    }
}

fn read_atomic_params() -> (bool, bool, f64, [f64; NUM_BANDS], u64, Spatial8dParams) {
    let eq_enabled = DSP_ENABLED.load(Ordering::Relaxed);
    let limiter = LIMITER_ENABLED.load(Ordering::Relaxed);
    let preamp_db = (PREAMP_MILLI_DB.load(Ordering::Relaxed) as f64) / 1000.0;
    let mut bands = [0.0_f64; NUM_BANDS];
    for i in 0..NUM_BANDS {
        bands[i] = (BAND_MILLI_DB[i].load(Ordering::Relaxed) as f64) / 1000.0;
    }
    let version = PARAMS_VERSION.load(Ordering::Acquire);

    let spatial = Spatial8dParams {
        enabled: SPATIAL_8D_ENABLED.load(Ordering::Relaxed),
        output_mode: SPATIAL_8D_OUTPUT_MODE.load(Ordering::Relaxed),
        speed_hz: (SPATIAL_8D_SPEED_MILLI_HZ.load(Ordering::Relaxed) as f64) / 1000.0,
        intensity: (SPATIAL_8D_INTENSITY_PERCENT.load(Ordering::Relaxed) as f64) / 100.0,
    };

    (eq_enabled, limiter, preamp_db, bands, version, spatial)
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

pub fn set_spatial_8d_parameters(
    enabled: bool,
    output_mode: i32,
    speed_hz: f32,
    intensity: f32,
) {
    SPATIAL_8D_ENABLED.store(enabled, Ordering::Relaxed);
    SPATIAL_8D_OUTPUT_MODE.store(if output_mode == 0 { 0 } else { 1 }, Ordering::Relaxed);
    SPATIAL_8D_SPEED_MILLI_HZ.store(
        (speed_hz.clamp(0.05, 0.50) * 1000.0).round() as i32,
        Ordering::Relaxed,
    );
    SPATIAL_8D_INTENSITY_PERCENT.store(
        (intensity.clamp(0.0, 1.0) * 100.0).round() as i32,
        Ordering::Relaxed,
    );
}

#[no_mangle]
pub extern "system" fn Java_com_auramusic_player_AuraRustDspBridge_nativeEngineInfo(
    env: JNIEnv,
    _class: JClass,
) -> jstring {
    let payload = serde_json::json!({
        "rustCrate": "aura_dsp",
        "engine": "Biquad IIR 5-band + 8D Orbital + Soft Limiter (MIT/Apache-2.0)",
        "arch": std::env::consts::ARCH,
        "bands": NUM_BANDS,
        "supportsSpatial8d": true,
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
pub extern "system" fn Java_com_auramusic_player_AuraRustDspBridge_nativeSetSpatial8dParameters(
    _env: JNIEnv,
    _class: JClass,
    enabled: jboolean,
    output_mode: jint,
    speed_hz: jfloat,
    intensity: jfloat,
) {
    set_spatial_8d_parameters(
        enabled == JNI_TRUE,
        output_mode,
        speed_hz,
        intensity,
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

    let (eq_enabled, limiter_on, preamp_db, bands, version, spatial) = read_atomic_params();
    if !eq_enabled && !spatial.enabled {
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
    if eq_enabled && chain.cached_version != version {
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
            chain.process_interleaved_f32_full(f32_slice, eq_enabled, limiter_on, &spatial);
        }
    } else {
        chain.process_interleaved_i16_full(slice, eq_enabled, limiter_on, &spatial);
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

    fn stereo_sine_wave(freq_hz: f64, sample_rate: u32, frames: usize) -> Vec<f32> {
        let mut out = Vec::with_capacity(frames * 2);
        for i in 0..frames {
            let s = (2.0 * PI * freq_hz * (i as f64) / (sample_rate as f64)).sin() as f32 * 0.35;
            out.push(s);
            out.push(s);
        }
        out
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

        let sub_bass = sine_wave(30.0, 48000, 4800);
        let mut boosted_sub = sub_bass.clone();
        chain.process_interleaved_f32(&mut boosted_sub, true);
        let sub_in_rms = rms(&sub_bass[1200..]);
        let sub_out_rms = rms(&boosted_sub[1200..]);
        assert!(
            sub_out_rms > sub_in_rms * 2.2,
            "60Hz shelf passband boost failed at 30Hz: in={sub_in_rms}, out={sub_out_rms}"
        );

        chain.reset_states();
        let corner = sine_wave(55.0, 48000, 4800);
        let mut boosted_corner = corner.clone();
        chain.process_interleaved_f32(&mut boosted_corner, true);
        let corner_in_rms = rms(&corner[1200..]);
        let corner_out_rms = rms(&boosted_corner[1200..]);
        assert!(
            corner_out_rms > corner_in_rms * 1.65,
            "60Hz corner boost failed at 55Hz: in={corner_in_rms}, out={corner_out_rms}"
        );

        chain.reset_states();
        let mids = sine_wave(2000.0, 48000, 4800);
        let mut mids_out = mids.clone();
        chain.process_interleaved_f32(&mut mids_out, true);
        let mids_ratio = rms(&mids_out[1200..]) / rms(&mids[1200..]);
        assert!(
            (mids_ratio - 1.0).abs() < 0.05,
            "60Hz shelf should not alter 2kHz mids: ratio={mids_ratio}"
        );
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
            assert!(
                val.unsigned_abs() <= 32705,
                "Soft limiter ceiling exceeded: {val}"
            );
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

    #[test]
    fn spatial_8d_headphones_creates_orbital_lr_pan_and_stays_finite() {
        let mut chain = DspChain::new(48000, 2);
        let spatial = Spatial8dParams {
            enabled: true,
            output_mode: 0, // Auriculares
            speed_hz: 0.50, // 2s por vuelta
            intensity: 1.0,
        };

        // 0.5 segundos -> un cuarto de órbita (~pan hacia la derecha)
        let mut buf = stereo_sine_wave(440.0, 48000, 24000);
        chain.process_interleaved_f32_full(&mut buf, false, true, &spatial);
        assert!(buf.iter().all(|s| s.is_finite()));

        // Evaluar último tramo cerca de pan=+1 (canal derecho > canal izquierdo)
        let tail = &buf[(20000 * 2)..];
        let left_tail: Vec<f32> = tail.iter().step_by(2).copied().collect();
        let right_tail: Vec<f32> = tail.iter().skip(1).step_by(2).copied().collect();
        assert!(
            rms(&right_tail) > rms(&left_tail) * 2.0,
            "Headphones 8D right orbit expected R > L: L={}, R={}",
            rms(&left_tail),
            rms(&right_tail)
        );
    }

    #[test]
    fn spatial_8d_speaker_mode_is_mono_sum_safe() {
        let mut chain = DspChain::new(48000, 2);
        let spatial = Spatial8dParams {
            enabled: true,
            output_mode: 1, // Altavoz
            speed_hz: 0.25,
            intensity: 0.90,
        };

        let input = stereo_sine_wave(1000.0, 48000, 48000);
        let mut processed = input.clone();
        chain.process_interleaved_f32_full(&mut processed, false, true, &spatial);
        assert!(processed.iter().all(|s| s.is_finite()));

        // Suma mono (L + R) * 0.5 no debe sufrir cancelación de fase ni caída brusca
        let mono_in: Vec<f32> = input.chunks_exact(2).map(|f| 0.5 * (f[0] + f[1])).collect();
        let mono_out: Vec<f32> = processed.chunks_exact(2).map(|f| 0.5 * (f[0] + f[1])).collect();
        let ratio = rms(&mono_out[2000..]) / rms(&mono_in[2000..]);
        assert!(
            ratio > 0.85 && ratio < 1.20,
            "Speaker mode must remain mono-safe without comb cancellation: ratio={ratio}"
        );
    }

    #[test]
    fn spatial_8d_disabled_leaves_signal_unchanged_without_eq() {
        let mut chain = DspChain::new(48000, 2);
        let input = stereo_sine_wave(880.0, 48000, 2000);
        let mut output = input.clone();
        chain.process_interleaved_f32_full(
            &mut output,
            false,
            false,
            &Spatial8dParams::default(),
        );
        let max_diff = input
            .iter()
            .zip(output.iter())
            .map(|(a, b)| (a - b).abs())
            .fold(0.0, f32::max);
        assert!(max_diff < 1e-6, "Bypass failed, diff={max_diff}");
    }
}
