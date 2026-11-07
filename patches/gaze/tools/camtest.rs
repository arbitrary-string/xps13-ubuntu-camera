// Local diagnostic only (not part of the patch): open a camera the way gazed does and pull frames.
use opencv::core::Mat;
use opencv::prelude::*;
use std::sync::atomic::AtomicBool;
use std::time::Instant;

fn mean_luma(m: &Mat) -> f64 {
    opencv::core::mean(m, &opencv::core::no_array()).map(|s| (s[0] + s[1] + s[2]) / 3.0).unwrap_or(-1.0)
}

fn main() -> anyhow::Result<()> {
    let args: Vec<String> = std::env::args().collect();
    let source = &args[1];
    let want_ir = args.get(2).is_some_and(|a| a == "ir");
    let start = Instant::now();
    let mut cam = if want_ir {
        gaze_vision::camera::Camera::open_ir_privileged(source, None)?
    } else {
        gaze_vision::camera::Camera::open_privileged(source)?
    };
    println!("opened after {:?}", start.elapsed());
    let stop = AtomicBool::new(false);
    let t0 = Instant::now();
    let mut n = 0;
    while t0.elapsed().as_secs() < 5 {
        match cam.next_interruptible(&stop) {
            Some(f) => { n += 1; println!("frame {n:3} t={:6.0}ms {}x{} luma={:.1}", t0.elapsed().as_secs_f64()*1000.0, f.cols(), f.rows(), mean_luma(&f)); }
            None => { println!("stream ended: {:?}", cam.take_stream_error()); break; }
        }
    }
    println!("{n} frames in {:?}", t0.elapsed());
    Ok(())
}
