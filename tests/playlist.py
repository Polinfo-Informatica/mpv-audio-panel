"""Check native audio playlist creation with cover art and nested mixed media."""

import argparse
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import wave
import zlib


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mpv", default="mpv")
    args = parser.parse_args()
    project = Path(__file__).resolve().parents[1]
    output = project / "test-output"
    output.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="playlist-", dir=output) as directory:
        root = Path(directory)
        media = root / "media"
        nested = media / "nested"
        nested.mkdir(parents=True)
        for path in (media / "first.wav", media / "second.wav", nested / "third.wav"):
            with wave.open(str(path), "wb") as audio:
                audio.setparams((1, 2, 8000, 0, "NONE", "not compressed"))
                audio.writeframes(b"\0\0" * 8000)
        def chunk(kind, data):
            return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
        png = b"\x89PNG\r\n\x1a\n"
        png += chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0))
        png += chunk(b"IDAT", zlib.compress(b"\0\xff\0\0")) + chunk(b"IEND", b"")
        (media / "cover.png").write_bytes(png)
        (nested / "cover.png").write_bytes(png)
        (media / "video.y4m").write_bytes(
            b"YUV4MPEG2 W2 H2 F1:1 Ip A1:1 C420jpeg\nFRAME\n" + b"\x10" * 4 + b"\x80" * 2
        )
        config = root / "config"
        (config / "scripts").mkdir(parents=True)
        (config / "mpv-audio-panel").mkdir()
        for relative in ("scripts/audio-panel.lua", "mpv-audio-panel/audio.conf"):
            shutil.copyfile(project / "config" / relative, config / relative)
        (config / "mpv.conf").write_text(
            "[default]\ninclude=~~/mpv-audio-panel/audio.conf\n", encoding="utf-8"
        )
        options = {"creationflags": subprocess.CREATE_NO_WINDOW} if os.name == "nt" else {}
        env = dict(os.environ, MPV_TEST_ROOT=str(media))
        result = subprocess.run(
            [args.mpv, f"--config-dir={config}", "--vo=null", "--ao=null",
             "--pause=yes", "--terminal=no", f"--log-file={root / 'mpv.log'}",
             f"--script={project / 'tests/playlist.lua'}", str(media / "first.wav")],
            env=env, timeout=12, **options,
        )
        report_path = media / "result.json"
        if not report_path.exists():
            raise RuntimeError((root / "mpv.log").read_text(encoding="utf-8", errors="replace"))
        report = json.loads(report_path.read_text(encoding="utf-8"))
        if result.returncode or report["failures"]:
            raise RuntimeError(str(report))
        print("Playlist checks passed: sibling audio only, no subdirectories or images, cover preserved.")


if __name__ == "__main__":
    main()
