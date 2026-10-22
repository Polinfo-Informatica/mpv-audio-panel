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
        total = 0
        env["MPV_TEST_CONFIG"] = str(project / "config")
        subprocess.run(
            [args.mpv, "--no-config", "--vo=null", "--ao=null", "--terminal=no", "--frames=1", "--keep-open=no", "--idle=no",
             f"--script={project / 'tests/video-safety.lua'}", f"--log-file={root / 'unit.log'}",
             str(root / "video.y4m")], env=env, timeout=10, check=True, **process_options,
        )
        unit_log = (root / "unit.log").read_text(encoding="utf-8", errors="replace")
        if "Video safety checks passed:" not in unit_log or "stack traceback" in unit_log:
            raise RuntimeError("Video safety unit checks failed: " + unit_log[-3000:])
        for mode in ("Audio", "Video", "Both"):
            config = root / mode
            (config / "scripts").mkdir(parents=True)
            (config / "mpv-audio-panel").mkdir()
            loader = "[default]\naudio-exclusive=yes\n"
            for component, script in (("audio", "audio-panel.lua"), ("video", "video-safety.lua")):
                if mode == "Both" or mode.lower() == component:
                    shutil.copyfile(project / "config/scripts" / script, config / "scripts" / script)
                    shutil.copyfile(project / "config/mpv-audio-panel" / f"{component}.conf", config / "mpv-audio-panel" / f"{component}.conf")
                    loader += f"include=~~/mpv-audio-panel/{component}.conf\n[default]\n"
            (config / "mpv.conf").write_text(loader, encoding="utf-8")
            env.update(MPV_TEST_CONFIG=str(config), MPV_TEST_MODE=mode)
            result = subprocess.run(
            [args.mpv, f"--config-dir={config}", "--idle=yes", "--pause=yes",
             "--vo=null", "--ao=null", "--terminal=no", "--autocreate-playlist=no",
             f"--watch-later-directory={root / 'watch-later'}", f"--log-file={root / 'mpv.log'}",
             f"--script={project / 'tests/runtime.lua'}"],
            env=env, timeout=30, **process_options,
        )
            report_file = root / "result.json"
            if not report_file.exists():
                detail = (root / "mpv.log").read_text(encoding="utf-8", errors="replace")
                errors = "\n".join(line for line in detail.splitlines() if "[runtime]" in line)
                raise RuntimeError(f"{mode}: no test report (exit {result.returncode})\n{errors}")
            report = json.loads(report_file.read_text(encoding="utf-8"))
            report_file.unlink()
            log = (root / "mpv.log").read_text(encoding="utf-8", errors="replace").lower()
            for error in ("error parsing option", "lua error", "stack traceback", "error loading script"):
                if error in log:
                    raise RuntimeError(f"{mode}: mpv log contains: {error}")
            if result.returncode or report["failures"]:
                raise RuntimeError(f"{mode}: {report}")
            total += report["cases"]
        print(f"Runtime checks passed: {total} mode transitions across Audio, Video and Both.")
        if not ffmpeg:
            print("HDR checks skipped: ffmpeg is not available.")


if __name__ == "__main__":
    main()
