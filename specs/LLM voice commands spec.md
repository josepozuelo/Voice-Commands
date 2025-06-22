Continuous Voice Command Capture – Design & Implementation

(OpenAI-based Command Classification · Voice-Activity Chunking)

⸻

Overview

VoiceControl enables continuous, low-latency, hands-free control by combining:
	1.	Always-on recording (no calibration or noise statistics).
	2.	Frame-level Voice-Activity Detection (VAD) to delimit utterances.
	3.	OpenAI Whisper for transcription.
	4.	OpenAI CommandClassifier that maps transcripts to seven JSON intents.

⸻

System Architecture

High-Level Flow

Mic → AudioEngine → VADChunker → Whisper → OpenAI CommandClassifier → CommandRouter
↑                                                                                ↓
└──────────────────────── Continuous Loop ───────────────────────────────────────┘

Core Components

#	Component	Responsibility
1	AudioEngine	Captures microphone audio; streams PCM buffers
2	VADChunker	Marks utterance start/end and emits speech-only chunks
3	WhisperService	Sends audio chunks to OpenAI Whisper (whisper-1)
4	CommandClassifier	Calls chat.completions with schema prompt; returns CommandJSON
5	CommandRouter	Executes shortcuts / selections / moves / etc.


⸻

Audio Processing Pipeline

Audio Capture

bufferSize = 1024 frames        // ≈ 64 ms @ 16 kHz
sampleRate = 16 kHz
format     = PCM Float32

AVAudioEngine streams a steady sequence of 1024-frame buffers.

VAD-Based Chunking
	•	Always recording: every buffer appends to the currentChunk.
	•	Frame-level VAD (20 ms granularity) labels each 20 ms slice as voiced or unvoiced.

State Management Hierarchy

Level 1: Frame-Level Detection (20ms granularity)
- Each frame labeled as voiced or unvoiced by VAD
- Raw input to state machine

Level 2: Counter-Based Tracking
voiceFrameCount     // consecutive voiced frames (resets on silence)
silenceFrameCount   // consecutive unvoiced frames (resets on voice)
totalSpeechFrames   // cumulative voiced frames in chunk (for validation)

Level 3: Chunk-Level State
inSpeech            // boolean gate: are we currently recording speech?
currentChunk        // audio buffer accumulating all frames

State Transitions
- Not Speaking → Speaking: When voiceFrameCount >= minSpeechFrames (5)
- Speaking → Chunk Emission: When silenceFrameCount >= trailingSilenceFrames (25)
- Chunk Validation: Only emit if totalSpeechFrames >= minSpeechFrames

Parameters

Name	Value	Purpose
frameLength	20 ms	VAD resolution
minSpeechFrames	5	100 ms: ignores coughs/clicks
trailingSilenceFrames	25	500 ms: utterance-end threshold
maxChunkLength	10 s	Safety cutoff
minChunkGap	200 ms	Prevents overlap

Algorithm

for each 20 ms frame:
    if VAD == voiced:
        voiceFrameCount   += 1
        silenceFrameCount  = 0
        totalSpeechFrames += 1
        if voiceFrameCount == minSpeechFrames:
            inSpeech = true                    // utterance starts
    else:                                      // frame is silence
        silenceFrameCount += 1
        voiceFrameCount    = 0

    if inSpeech and silenceFrameCount >= trailingSilenceFrames:
        emitChunkIfSpeech()                    // see below
        resetState()

    if chunkDuration >= maxChunkLength:
        emitChunkIfSpeech()
        resetState()

emitChunkIfSpeech()

if totalSpeechFrames >= minSpeechFrames:       // chunk contains speech
    trimLeadingTrailingSilence()
    WhisperService.enqueue(currentChunk)

Chunks composed entirely of silence are discarded. The next buffer begins a fresh chunk immediately; there is no calibration delay.

Example Scenarios

Scenario 1: Normal Speech
[silence][speech for 2s][silence for 500ms] → Emit chunk
- voiceFrameCount hits 5 → inSpeech = true
- Speech continues, totalSpeechFrames accumulates
- silenceFrameCount hits 25 → emit chunk (passes validation)

Scenario 2: Brief Noise/Cough
[silence][3 voiced frames][silence] → No emission
- voiceFrameCount only reaches 3 → inSpeech stays false
- No chunk emission triggered

Scenario 3: Long Pause Mid-Sentence
[speech][400ms silence][more speech] → Continues same chunk
- silenceFrameCount reaches 20 but < 25
- voiceFrameCount resets and climbs again
- Chunk continues accumulating both utterances

⸻

Command Processing Pipeline

1 · Transcription
	•	WhisperService uploads the trimmed chunk to OpenAI Whisper (whisper-1).
	•	Returns plain text.

2 · Command Classification

CommandClassifier.classify(transcript) -> CommandJSON

Calls chat.completions with the ultra-compact schema prompt (next section).

3 · Execution

Intent	Destination
shortcut · select · move · tab · overlay	AccessibilityBridge
dictation	TextBuffer
edit	EditModeEngine
none	CommandHUD (“Please repeat”)


⸻

Ultra-Compact Classification Prompt

System Prompt
Map a spoken phrase to exactly one JSON object from the list below and return only that JSON.
If nothing matches, output {"intent":"none"}.

{ "intent":"shortcut", "key":"C", "modifiers":["command","shift"] }
{ "intent":"select",   "unit":"char|word|sentence|paragraph|line|all",
                        "direction":"this|next|prev", "count":1 }
{ "intent":"move",     "direction":"up|down|left|right|forward|back",
                        "unit":"char|word|sentence|paragraph|line|page|screen",
                        "count":1 }
{ "intent":"tab",      "action":"new|close|next|prev|show", "index":0 }
{ "intent":"overlay",  "action":"show|hide|click", "target":7 }
{ "intent":"dictation","text":"Hello, how are you?" }
{ "intent":"edit",     "instruction":"Replace the second sentence with “Goodbye.”" }

Model: gpt-4.1-mini-2025-04-14

⸻

Performance Characteristics

Stage	Latency (typical)
Audio buffer	64 ms
VAD trailing silence	0.5 s
Chunk gap	0.2 s
Whisper API	0.5 – 2.0 s
OpenAI classification	0.15 – 0.30 s
Routing & execution	< 10 ms
End-to-end	1.46 – 3.10 s


⸻

Memory Usage
	•	Audio buffer: ≈ 32 KB / s
	•	Maximum chunk: ≈ 320 KB (10 s)

⸻

Debug Logging

VAD — voiced:12  silence:3  inSpeech:true  totalSpeech:47

Logged every 2 s for rapid verification.

⸻

Key Classes

File	Responsibility
AudioEngine.swift	AVAudioEngine lifecycle, PCM buffering
VADChunker.swift	Frame-level VAD, chunk boundary detection
WhisperService.swift	OpenAI Whisper calls
CommandClassifier.swift	OpenAI Chat-based intent mapping
CommandRouter.swift	Dispatches CommandJSON
AccessibilityBridge.swift	Executes macOS accessibility actions


⸻

Operating Modes

Mode	Activation	Behaviour
Single-Command	Hold hotkey	Records one utterance; stops afterward
Continuous (default)	Toggle ⌃⇧V	Always listening with VAD chunking


⸻

Summary

This VAD-based design streams audio continuously, starts a chunk only when genuine speech is detected, and finalises it after 500 ms of trailing silence. Pure-silence chunks are discarded, ensuring Whisper receives only meaningful audio. Combined with the OpenAI Whisper transcriber and JSON-intent CommandClassifier, the system offers natural, environment-agnostic voice control with minimal latency and without calibration or dynamic thresholds.