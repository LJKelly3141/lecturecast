# Kokoro voice runner for lecturecast. Loads Kokoro once, then answers one
# JSON request per stdin line with one JSON reply per stdout line:
#   request: {"text": str, "voice": str, "speed": number, "out": "<path>.wav"}
#   reply:   {"ok": true, "seconds": number, "words": [{"text", "start", "end"}]}
#            or {"ok": false, "error": str}
# The first line written is {"ready": true, "version": str}.
import json
import os
import sys
import importlib.metadata

# Replies go to the real stdout; everything else that prints (libraries,
# model downloads, pip run by misaki) is sent to stderr so it cannot be
# mistaken for a reply.
_replies = os.fdopen(os.dup(1), "w")
os.dup2(2, 1)
sys.stdout = sys.stderr


def say(obj):
    _replies.write(json.dumps(obj) + "\n")
    _replies.flush()


def main():
    import numpy as np
    import soundfile as sf
    from kokoro import KPipeline

    rate = 24000
    pipes = {}
    say({"ready": True, "version": importlib.metadata.version("kokoro")})
    for line in sys.stdin:
        if not line.strip():
            continue
        try:
            req = json.loads(line)
            voice = req["voice"]
            lang = voice[0]
            if lang not in pipes:
                pipes[lang] = KPipeline(lang_code=lang, repo_id="hexgrad/Kokoro-82M")
            try:
                results = list(pipes[lang](req["text"], voice=voice, speed=float(req.get("speed", 1))))
            except Exception as e:
                raise RuntimeError("voice " + voice + ": " + str(e)) from e
            chunks, words, offset = [], [], 0.0
            for r in results:
                if r.audio is None:
                    continue
                a = r.audio.numpy() if hasattr(r.audio, "numpy") else np.asarray(r.audio)
                for t in r.tokens or []:
                    if t.start_ts is None or t.end_ts is None:
                        continue
                    if not any(c.isalnum() for c in t.text):
                        continue
                    words.append({"text": t.text, "start": offset + t.start_ts, "end": offset + t.end_ts})
                chunks.append(a)
                offset += len(a) / rate
            if not chunks:
                say({"ok": False, "error": "Kokoro returned no audio."})
                continue
            sf.write(req["out"], np.concatenate(chunks), rate)
            say({"ok": True, "seconds": offset, "words": words})
        except Exception as e:
            say({"ok": False, "error": str(e).replace("\n", " ")})


if __name__ == "__main__":
    main()
