extends Node

## LocalLLM: Offline dialogue service powered by NobodyWho + a small GGUF model.
##
## Several tiny models are supported. The service loads the best one that fits
## and falls back down the list if a model is missing or unsupported:
##   1. Gemma 3 1B IT  - best natural first-person dialogue
##   2. LFM2-700M      - built for on-device chat, faster and a bit blunter
##   3. Qwen3 0.6B     - previous default, slower and needs non-streaming
##   4. LFM2-350M      - tiny last resort; loads anywhere, rambles a bit
##
## Inference is serialized through a queue so many NPCs share one model.
## Models that stream cleanly stop at the first complete sentence to keep lines
## short and Pi latency low; the rest use a single blocking completion.

signal model_ready
signal model_failed(error_message: String)
signal line_generated(speaker: String, text: String)

const MODEL_CANDIDATES: Array = [
	{
		"file": "gemma-3-1b-it-Q4_K_M.gguf",
		"label": "Gemma-3-1B",
		"temperature": 0.85,
		"top_k": 40,
		"top_p": 0.92,
		"repeat_penalty": 1.10,
		"thinking": false,
	},
	{
		"file": "LFM2-700M-Q4_K_M.gguf",
		"label": "LFM2-700M",
		"temperature": 0.85,
		"top_k": 40,
		"top_p": 0.92,
		"repeat_penalty": 1.15,
		"thinking": false,
	},
	{
		"file": "Qwen_Qwen3-0.6B-Q4_K_M.gguf",
		"label": "Qwen3-0.6B",
		"temperature": 0.80,
		"top_k": 40,
		"top_p": 0.90,
		"repeat_penalty": 1.15,
		"thinking": true,
		# next_token() never resolves on this build, so use blocking completion.
		"streaming": false,
	},
	{
		"file": "LFM2-350M-Q4_K_M.gguf",
		"label": "LFM2-350M",
		"temperature": 0.80,
		"top_k": 40,
		"top_p": 0.90,
		"repeat_penalty": 1.12,
		"thinking": false,
	},
]

## On a Pi the Vulkan backend is a software fallback and is ~25x slower than
## the CPU backend, so it is disabled before the model is loaded.
const DISABLE_VULKAN_ENV := "GGML_DISABLE_VULKAN"

## Force a specific model by label (e.g. "Gemma-3-1B"). Empty = auto order.
@export var preferred_model: String = ""
@export var enabled: bool = true
@export var n_ctx: int = 512
@export var n_threads: int = 3
@export var max_response_chars: int = 110
@export var max_queued_requests: int = 2
## Hard ceiling on generated tokens. Lines are one sentence, so 48 is plenty.
@export var max_new_tokens: int = 48
## Safety net for one line: stop a generation that never finishes. This is a
## ceiling, not a target, so it sits well above a normal Pi prefill + reply.
@export var generation_timeout: float = 45.0

var _model: Variant = null
var _chat: Variant = null
var _is_ready: bool = false
var _is_failed: bool = false
var _failure_reason: String = ""
var _model_label: String = ""
var _queue: Array[Dictionary] = []
var _busy: bool = false

## Bumped for every generation. A watchdog captures the value it started with
## and only calls stop_generation() if it still matches, so a late timer can
## never cut off the next NPC's line.
var _generation_id: int = 0

## True when the watchdog cut the current generation short. Such a line is only
## used if it still ends in punctuation, otherwise the caller shows a fallback.
var _generation_cut: bool = false

## True when this model's next_token() stream is reliable and can be stopped
## after the first sentence. Qwen3 hangs on next_token(), so it uses the
## blocking completed() path instead.
var _streaming: bool = true

## Lower-case names of every islander, used to reject third-person narration.
var _known_names: PackedStringArray = []

## Recently spoken lines across every NPC, so the same bark never repeats.
var _recent_outputs: Array[String] = []
const MAX_RECENT_OUTPUTS: int = 40

## A tiny per-request signal object so callers can `await` a generated line
## without the service needing to know anything about them.
class LineRequest extends RefCounted:
	signal finished(text: String)

func _ready() -> void:
	if not enabled:
		return
	# Optional override, handy for testing: NPC_MODEL=Gemma-3-1B godot ...
	var env_model := OS.get_environment("NPC_MODEL")
	if not env_model.is_empty():
		preferred_model = env_model
	# Must be set before the model is loaded; this makes llama.cpp skip Vulkan.
	OS.set_environment(DISABLE_VULKAN_ENV, "1")
	_build_known_names()
	call_deferred("_load_model")

func _build_known_names() -> void:
	_known_names = []
	for entry in NPCDefinitions.NPC_DEFINITIONS:
		if entry is Dictionary:
			var n := str(entry.get("name", "")).strip_edges().to_lower()
			if not n.is_empty():
				_known_names.append(n)

func _load_model() -> void:
	if not ClassDB.class_exists("NobodyWhoModel") or not ClassDB.class_exists("NobodyWhoChat"):
		_fail("NobodyWho GDExtension is not loaded. Reinstall addons/nobodywho and restart the editor.")
		return

	# Suppress llama.cpp verbose logging BEFORE model creation
	if ClassDB.class_exists("NobodyWho"):
		NobodyWho.set_log_level("ERROR")

	var ordered: Array = []
	for candidate in MODEL_CANDIDATES:
		if preferred_model.is_empty() or str(candidate["label"]) == preferred_model:
			ordered.append(candidate)
	if ordered.is_empty():
		ordered = MODEL_CANDIDATES.duplicate()
	# If a preferred model was requested, append the rest as fallbacks.
	for candidate in MODEL_CANDIDATES:
		if not ordered.has(candidate):
			ordered.append(candidate)

	for candidate in ordered:
		if await _try_load(candidate):
			return

	_fail("No supported GGUF model could be loaded. Checked: %s" % _candidate_paths())

func _try_load(candidate: Dictionary) -> bool:
	var path: String = _resolve_model_path(str(candidate["file"]))
	if not FileAccess.file_exists(path):
		return false

	var model = await NobodyWhoModel.create(path, {
		"use_gpu": false,
	})
	if model == null:
		return false
	_model = model

	var template_vars: Dictionary = {}
	if bool(candidate.get("thinking", false)):
		template_vars["enable_thinking"] = false

	var chat = await NobodyWhoChat.create(_model, {
		"n_ctx": n_ctx,
		"n_threads": n_threads,
		"context_shift": false,
		"template_variables": template_vars,
		"sampler": NobodyWhoSamplerBuilder.new()
			.top_k(int(candidate["top_k"]))
			.top_p(float(candidate["top_p"]), 1)
			.temperature(float(candidate["temperature"]))
			.penalties(64, float(candidate["repeat_penalty"]), 0.0, 0.0)
			.dist(),
	})
	if chat == null:
		_model = null
		return false

	_chat = chat
	_model_label = str(candidate["label"])
	_streaming = bool(candidate.get("streaming", true))
	_is_ready = true
	model_ready.emit()
	_pump()
	return true

func _candidate_paths() -> String:
	var paths: Array[String] = []
	for candidate in MODEL_CANDIDATES:
		paths.append(_resolve_model_path(str(candidate["file"])))
	return ", ".join(paths)

## Look for a GGUF in the usual places. Models are kept outside the project by
## default so the repository stays small; drop them in any of these folders:
##   $NPC_MODEL_DIR, res://models, user://models, ~/.local/share/pixel-traks-models
func _resolve_model_path(filename: String) -> String:
	var checked: Array[String] = []
	var env_dir := OS.get_environment("NPC_MODEL_DIR")
	if not env_dir.is_empty():
		checked.append(env_dir.path_join(filename))
	checked.append("res://models".path_join(filename))
	checked.append(ProjectSettings.globalize_path("user://models").path_join(filename))
	var home := OS.get_environment("HOME")
	if not home.is_empty():
		checked.append(home.path_join(".local/share/pixel-traks-models").path_join(filename))
		checked.append(home.path_join("pixel-traks-models").path_join(filename))
	for candidate in checked:
		if FileAccess.file_exists(candidate):
			return candidate
	return checked[0]

func _fail(message: String) -> void:
	_is_failed = true
	_failure_reason = message
	push_error("[LocalLLM] " + message)
	model_failed.emit(message)
	# Resolve anything that was already waiting so callers do not hang.
	while not _queue.is_empty():
		var item: Dictionary = _queue.pop_front()
		var req: LineRequest = item["req"]
		req.finished.emit("")

func is_ready() -> bool:
	return _is_ready

func is_failed() -> bool:
	return _is_failed

func get_failure_reason() -> String:
	return _failure_reason

func get_model_label() -> String:
	return _model_label

## True when a new conversation should wait instead of piling more work onto
## the queue. Existing conversations may still queue their next line.
func is_backlogged() -> bool:
	return _busy and _queue.size() >= max_queued_requests

## Reset the model's chat history between different NPC pairs. `complete()`
## already replaces the history each call, but this keeps KV state clean.
func reset_chat_history() -> void:
	if _chat != null and _is_ready:
		_chat.reset_history()

## Generate one spoken line.
## - system_prompt: who the speaker is and how they should talk
## - history: prior turns as [{"role": "user"|"assistant", "content": String}]
## - user_prompt: the current thing the speaker is responding to
## Returns "" when the model is unavailable; callers should use a fallback.
func generate_line(system_prompt: String, history: Array, user_prompt: String) -> String:
	if not _is_ready or _chat == null:
		return ""

	var req := LineRequest.new()
	_queue.append({
		"req": req,
		"system_prompt": system_prompt,
		"history": history.duplicate(true),
		"user_prompt": user_prompt,
	})
	_pump()

	var text: String = await req.finished
	return text

func _pump() -> void:
	if _busy or _queue.is_empty() or not _is_ready:
		return
	_busy = true
	_process_next()

func _process_next() -> void:
	if _queue.is_empty() or not _is_ready:
		_busy = false
		return

	var item: Dictionary = _queue.pop_front()
	var req: LineRequest = item["req"]
	var text: String = await _run_request(item)

	req.finished.emit(text)
	_process_next()

func _run_request(item: Dictionary) -> String:
	var messages: Array = [
		{"role": "system", "content": str(item["system_prompt"])},
	]
	var history: Array = item["history"]
	for turn in history:
		if turn is Dictionary:
			messages.append(turn)
	messages.append({"role": "user", "content": str(item["user_prompt"])})

	var stream = _chat.complete(messages, {})
	if stream == null:
		return ""
	_generation_id += 1
	var gen_id: int = _generation_id
	_generation_cut = false
	_start_watchdog(gen_id)
	var raw: String = ""
	if _streaming:
		raw = await _collect_stream(stream)
	else:
		var raw_value = await stream.completed()
		raw = str(raw_value) if raw_value != null else ""
	if gen_id == _generation_id:
		# Generation finished on its own; retire this watchdog.
		_generation_id += 1
	if raw.is_empty():
		return ""
	# A watchdog-truncated line is only usable if it happens to end cleanly.
	if _generation_cut and not _ends_sentence(raw):
		return ""

	var text: String = _clean_line(raw, str(item["system_prompt"]))
	if text.is_empty():
		return ""
	if _is_recent_duplicate(text):
		return ""
	_track_recent(text)
	line_generated.emit("", text)
	return text

## Read tokens until the first spoken sentence ends (or a hard token cap),
## then ask llama.cpp to stop. This keeps replies short and Pi latency low.
func _collect_stream(stream) -> String:
	var text: String = ""
	var tokens: int = 0
	while true:
		var piece = await stream.next_token()
		if piece == null:
			break
		var chunk: String = str(piece)
		if not chunk.is_empty():
			text += chunk
			tokens += 1
		if tokens >= 4 and _ends_sentence(text):
			_chat.stop_generation()
			break
		if tokens >= max_new_tokens:
			_chat.stop_generation()
			break
	return text

func _ends_sentence(text: String) -> bool:
	var t: String = text.strip_edges()
	# Ignore a closing quote after the punctuation.
	while not t.is_empty() and _ends_with_any(t, ["\"", "'", "”", "’"]):
		t = t.substr(0, t.length() - 1).strip_edges()
	if t.length() < 6:
		return false
	var last: String = t.substr(t.length() - 1, 1)
	return last == "." or last == "!" or last == "?"

## Stop a runaway generation after `generation_timeout` seconds. The model keeps
## whatever text it produced so far, which the sanitizer trims to one sentence.
func _start_watchdog(gen_id: int) -> void:
	if generation_timeout <= 0.0:
		return
	var tree := get_tree()
	if tree == null:
		return
	await tree.create_timer(generation_timeout).timeout
	if gen_id != _generation_id:
		return
	_generation_cut = true
	if _chat != null:
		_chat.stop_generation()

func _clean_line(raw: String, system_prompt: String) -> String:
	var text := raw.strip_edges()

	# Drop stage directions such as *smiles* or (chuckles).
	var stage_regex := RegEx.create_from_string(r"\*[^*]+\*|\([^)]+\)")
	text = stage_regex.sub(text, "", true).strip_edges()

	# Some models prepend their own name; strip it.
	var name_match := RegEx.create_from_string(r"^([A-Z][A-Za-z' -]{1,24}):\s*")
	var match_result := name_match.search(text)
	if match_result != null:
		text = text.substr(match_result.get_end()).strip_edges()

	# Normalise whitespace and strip wrapping quotes.
	text = text.replace("\r", " ").replace("\n", " ").replace("\t", " ")
	text = text.replace("  ", " ").replace("  ", " ").strip_edges()
	var open_quotes := ["\"", "'", "“", "‘", "«"]
	var close_quotes := ["\"", "'", "”", "’", "»"]
	while _starts_with_any(text, open_quotes):
		text = text.substr(1).strip_edges()
	while _ends_with_any(text, close_quotes):
		text = text.substr(0, text.length() - 1).strip_edges()

	# Avoid Dialogic interpreting square brackets as commands.
	text = text.replace("[", "(").replace("]", ")")

	# Keep only the first spoken sentence; small models like to ramble.
	text = _first_sentence(text)
	# Then cap the length, preferring a natural comma break over a hard cut.
	text = _limit_words(text, 14)

	if text.length() > max_response_chars:
		# Cut on a word boundary so a hard cap never leaves half a word.
		text = text.left(max_response_chars)
		var last_space := text.rfind(" ")
		if last_space > 20:
			text = text.left(last_space)
		text = text.strip_edges().trim_suffix(",").trim_suffix(";").strip_edges()
		if not _ends_with_any(text, [".", "!", "?"]):
			text += "."

	# Reject third-person narration ("John was walking...", "Kaia is tired...").
	if _is_narration(text, system_prompt):
		return ""
	# Reject broken output with missing words ("has a  on his back").
	if _has_gaps(text):
		return ""
	# Reject echoes of the instructions themselves.
	var lowered := text.to_lower()
	if lowered.is_empty() or lowered.contains("one short") or lowered.contains("first person") \
			or lowered.contains("stay in character") or lowered.contains("as an ai"):
		return ""
	# Need at least two real words to be a line of dialogue.
	if _word_count(text) < 2:
		return ""
	return text

func _limit_words(text: String, limit: int) -> String:
	var words := text.split(" ", false)
	if words.size() <= limit:
		return text
	# Only shorten when there is a clause break just before the cap; a hard cut
	# mid-clause reads worse than a slightly long sentence.
	var cut := -1
	for i in range(limit - 1, maxi(5, limit - 6), -1):
		var w := str(words[i]).strip_edges()
		if w.ends_with(",") or w.ends_with(";") or w.ends_with("—"):
			cut = i + 1
			break
	if cut < 0:
		return text
	var kept := " ".join(words.slice(0, cut)).strip_edges()
	kept = kept.trim_suffix(",").trim_suffix(";").trim_suffix("—").strip_edges()
	if kept.is_empty():
		return text
	if not _ends_with_any(kept, [".", "!", "?"]):
		kept += "."
	return kept

func _starts_with_any(text: String, prefixes: Array) -> bool:
	for prefix in prefixes:
		if text.begins_with(str(prefix)):
			return true
	return false

func _ends_with_any(text: String, suffixes: Array) -> bool:
	for suffix in suffixes:
		if text.ends_with(str(suffix)):
			return true
	return false

func _first_sentence(text: String) -> String:
	var best: int = -1
	for i in range(text.length()):
		var c := text.substr(i, 1)
		if c == "." or c == "!" or c == "?":
			# Avoid cutting decimals or ellipses too aggressively.
			var nxt := text.substr(i + 1, 1)
			if c == "." and nxt == ".":
				continue
			if i >= 5:
				best = i
				break
	if best >= 0 and best < text.length() - 1:
		return text.substr(0, best + 1).strip_edges()
	return text

func _is_narration(text: String, _system_prompt: String) -> bool:
	var t := text.strip_edges().to_lower()
	if t.is_empty():
		return false
	# Pronoun narration ("She was tired.", "They walked off.").
	var pronoun := RegEx.create_from_string(
		r"^(?:he|she|they)\s+(?:was|were|walked|walks|looked|looks|nodded|smiled|turned|stood|began)\b"
	)
	if pronoun.search(t) != null:
		return true
	# Any islander's name followed by a narration verb ("John was scanning...").
	for name in _known_names:
		var pattern := "^%s\\s+(?:was|were|walked|walks|looked|looks|nodded|smiled|turned|stood|began)\\b" % name.replace(" ", "\\s+")
		var re := RegEx.create_from_string(pattern)
		if re.search(t) != null:
			return true
	return false

func _has_gaps(text: String) -> bool:
	# A determiner/possessive immediately followed by a preposition usually
	# means the model dropped a word ("has a  on his back" -> "a on").
	var broken := RegEx.create_from_string(
		r"\b(?:a|an|the|his|her|my|your|their|its)\s+(?:a|an|the|on|in|under|of|at|to|with|for|from|by)\b"
	)
	if broken.search(text.to_lower()) != null:
		return true
	# Several one-letter words in a row is another sign of broken output.
	var words := text.split(" ", false)
	var singles := 0
	for w in words:
		if w.length() == 1 and w.to_lower() in ["a", "i", "s", "t", "n"]:
			singles += 1
			if singles >= 3:
				return true
		else:
			singles = 0
	return false

func _word_count(text: String) -> int:
	return text.split(" ", false).size()

func _is_recent_duplicate(text: String) -> bool:
	var lower := text.to_lower()
	for recent in _recent_outputs:
		if recent.to_lower() == lower:
			return true
	return false

func _track_recent(text: String) -> void:
	_recent_outputs.append(text)
	if _recent_outputs.size() > MAX_RECENT_OUTPUTS:
		_recent_outputs.remove_at(0)
