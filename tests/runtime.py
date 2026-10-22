"""Exercise audio/video mode changes with synthetic media and a real mpv process."""

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import wave


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mpv", default="mpv")
    args = parser.parse_args()
    project = Path(__file__).resolve().parents[1]
    output = project / "test-output"
    output.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="runtime-", dir=output) as directory:
        root = Path(directory)
        with wave.open(str(root / "audio.wav"), "wb") as audio:
            audio.setparams((1, 2, 8000, 0, "NONE", "not compressed"))
            audio.writeframes(b"\0\0" * 16000)
        shutil.copyfile(root / "audio.wav", root / "unknown.mp4")
        frame = b"\x10" * (16 * 16) + b"\x80" * (16 * 16 // 2)
        (root / "video.y4m").write_bytes(
            b"YUV4MPEG2 W16 H16 F2:1 Ip A1:1 C420jpeg\n" + (b"FRAME\n" + frame) * 4
        )
        shutil.copyfile(root / "video.y4m", root / "unknown.data")
        env = dict(os.environ, MPV_TEST_ROOT=str(root))
        ffmpeg = shutil.which("ffmpeg")
        process_options = {"creationflags": subprocess.CREATE_NO_WINDOW} if os.name == "nt" else {}
        if ffmpeg:
            for name, transfer in (("pq", "smpte2084"), ("hlg", "arib-std-b67")):
                subprocess.run(
                    [ffmpeg, "-v", "error", "-f", "lavfi", "-i", "color=c=black:s=32x32:r=2:d=2",
                     "-vf", f"setparams=color_primaries=bt2020:color_trc={transfer}:colorspace=bt2020nc",
                     "-c:v", "libx264", "-pix_fmt", "yuv420p", "-x264-params",
                     f"colorprim=bt2020:transfer={transfer}:colormatrix=bt2020nc", str(root / f"{name}.mkv")],
                    check=True, timeout=15, **process_options,
                )
            env["MPV_TEST_HDR"] = "1"
        result = subprocess.run(
            [args.mpv, f"--config-dir={project / 'config'}", "--idle=yes", "--pause=yes",
             "--vo=null", "--ao=null", "--terminal=no", "--autocreate-playlist=no",
             f"--watch-later-directory={root / 'watch-later'}", f"--log-file={root / 'mpv.log'}",
             f"--script={project / 'tests/runtime.lua'}"],
            env=env, timeout=30, **process_options,
        )
        report_file = root / "result.json"
        if not report_file.exists():
            raise RuntimeError(f"mpv produced no test report (exit {result.returncode})")
        report = json.loads(report_file.read_text(encoding="utf-8"))
        log = (root / "mpv.log").read_text(encoding="utf-8", errors="replace").lower()
        for error in ("error parsing option", "lua error", "stack traceback", "error loading script"):
            if error in log:
                raise RuntimeError(f"mpv log contains: {error}")
        if result.returncode or report["failures"]:
            raise RuntimeError(report)
        print(f"Runtime checks passed: {report['cases']} mode transitions.")
        if not ffmpeg:
            print("HDR checks skipped: ffmpeg is not available.")


if __name__ == "__main__":
    main()
