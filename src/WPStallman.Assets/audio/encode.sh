# Input: founder_source.wav (or .mp3). Adjust path as needed.

# 1) Preprocess: trim leading silence & normalize dynamics (optional but recommended)
ffmpeg -y -i founder_source.wav \
  -af "silenceremove=start_periods=1:start_threshold=-40dB:start_silence=0.25, dynaudnorm" \
  -ar 48000 -ac 2 \
  founder_clean.wav

# 2) WebM (Opus) — preferred for size+latency
ffmpeg -y -i founder_clean.wav \
  -c:a libopus -b:a 96k -frame_duration 60 -application voip \
  founder.webm

# 3) Ogg (Vorbis) — broadly supported fallback
ffmpeg -y -i founder_clean.wav \
  -c:a libvorbis -q:a 5 \
  founder.ogg

# 4) MP3 — universal fallback
ffmpeg -y -i founder_clean.wav \
  -c:a libmp3lame -b:a 128k -ar 48000 -ac 2 \
  founder.mp3

