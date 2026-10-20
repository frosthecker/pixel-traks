extends Node

## GroqService: Connects Godot & Dialogic to Groq Cloud LLMs (Llama-3.3-70b, Llama-3.1-8b, etc.)
## Endpoint: https://api.groq.com/openai/v1/chat/completions

signal request_started
signal request_completed(response_text: String)
signal request_failed(error_message: String)

@export_category("Groq Settings")
@export var api_key: String = ""
@export var model: String = "openai/gpt-oss-20b"
@export var temperature: float = 0.7
@export var max_tokens: int = 300
@export var timeout_seconds: float = 10.0

const FALLBACK_MODELS: Array[String] = [
	"openai/gpt-oss-20b",
	"qwen/qwen3.8-27b",
	"openai/gpt-oss-120b"
]

const GROQ_API_URL := "https://api.groq.com/openai/v1/chat/completions"
const CONFIG_FILE_PATH := "res://groq_config.json"
const USER_CONFIG_PATH := "user://groq_config.json"

func _ready() -> void:
	load_config()

## Load API key and model from environment, user config, or project config.
func load_config() -> void:
	# 1. Check OS environment variable
	var env_key := OS.get_environment("GROQ_API_KEY").strip_edges()
	if not env_key.is_empty():
		api_key = env_key
		print("[GroqService] Loaded API key from GROQ_API_KEY environment variable.")
		return

	# 2. Check user config file (writable location)
	if FileAccess.file_exists(USER_CONFIG_PATH):
		if _load_json_config(USER_CONFIG_PATH):
			print("[GroqService] Loaded configuration from %s." % USER_CONFIG_PATH)
			return

	# 3. Check project config file (res://)
	if FileAccess.file_exists(CONFIG_FILE_PATH):
		if _load_json_config(CONFIG_FILE_PATH):
			print("[GroqService] Loaded configuration from %s." % CONFIG_FILE_PATH)
			return

	if api_key.is_empty() or api_key == "YOUR_GROQ_API_KEY_HERE":
		print("[GroqService] No Groq API key set. Please set GROQ_API_KEY or configure res://groq_config.json.")

func _load_json_config(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var content := file.get_as_text()
	file.close()

	var data = JSON.parse_string(content)
	if typeof(data) != TYPE_DICTIONARY:
		return false

	var key_val: String = str(data.get("api_key", "")).strip_edges()
	if not key_val.is_empty() and key_val != "YOUR_GROQ_API_KEY_HERE":
		api_key = key_val
	if data.has("model"):
		model = str(data.get("model", model))
	if data.has("temperature"):
		temperature = float(data.get("temperature", temperature))
	if data.has("max_tokens"):
		max_tokens = int(data.get("max_tokens", max_tokens))
	return true

## Save configuration to user:// or res://
func save_config(new_api_key: String, new_model: String = "", save_to_user: bool = true) -> bool:
	var target_path := USER_CONFIG_PATH if save_to_user else CONFIG_FILE_PATH
	var config_data := {
		"api_key": new_api_key.strip_edges(),
		"model": new_model if not new_model.is_empty() else model,
		"temperature": temperature,
		"max_tokens": max_tokens
	}
	var file := FileAccess.open(target_path, FileAccess.WRITE)
	if file == null:
		printerr("[GroqService] Failed to open config file for writing: ", target_path)
		return false
	file.store_string(JSON.stringify(config_data, "\t"))
	file.close()
	api_key = config_data["api_key"]
	if not new_model.is_empty():
		model = new_model
	print("[GroqService] Configuration saved to: ", target_path)
	return true

## Returns true if a valid API key appears to be configured.
func has_valid_api_key() -> bool:
	var clean := api_key.strip_edges()
	return not clean.is_empty() and clean != "YOUR_GROQ_API_KEY_HERE"

## Low-level async chat completion request to Groq API.
func send_chat_request(messages: Array, model_override: String = "", response_format: Dictionary = {}) -> Dictionary:
	if not has_valid_api_key():
		var err := "Groq API key is not configured. Please add your key to groq_config.json."
		request_failed.emit(err)
		return {"success": false, "error": err, "status_code": 0}

	var active_model := model_override if not model_override.is_empty() else model
	var http_request := HTTPRequest.new()
	http_request.timeout = timeout_seconds
	add_child(http_request)

	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer %s" % api_key.strip_edges(),
		"User-Agent: GodotEngine/4.x (Traks)"
	])

	var payload := {
		"model": active_model,
		"messages": messages,
		"temperature": temperature,
		"max_tokens": max_tokens
	}
	if not response_format.is_empty():
		payload["response_format"] = response_format

	var json_body := JSON.stringify(payload)
	request_started.emit()

	var req_err := http_request.request(GROQ_API_URL, headers, HTTPClient.METHOD_POST, json_body)
	if req_err != OK:
		http_request.queue_free()
		var msg := "Failed to dispatch HTTP request (Error code: %d)" % req_err
		request_failed.emit(msg)
		return {"success": false, "error": msg, "status_code": 0}

	var completed_args = await http_request.request_completed
	http_request.queue_free()

	var result_code: int = completed_args[0]
	var http_status: int = completed_args[1]
	var response_body: PackedByteArray = completed_args[3]
	var response_text := response_body.get_string_from_utf8()

	if result_code != HTTPRequest.RESULT_SUCCESS:
		var err_msg := "HTTPRequest failed with transport code %d (HTTP %d)" % [result_code, http_status]
		request_failed.emit(err_msg)
		return {"success": false, "error": err_msg, "status_code": http_status}

	if http_status != 200:
		var err_msg := "Groq API returned HTTP %d: %s" % [http_status, response_text]
		request_failed.emit(err_msg)
		return {"success": false, "error": err_msg, "status_code": http_status, "raw": response_text}

	var parsed = JSON.parse_string(response_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		var err_msg := "Failed to parse Groq response JSON"
		request_failed.emit(err_msg)
		return {"success": false, "error": err_msg, "status_code": http_status}

	var choices: Array = parsed.get("choices", [])
	if choices.is_empty():
		var err_msg := "Groq returned empty choices list"
		request_failed.emit(err_msg)
		return {"success": false, "error": err_msg, "status_code": http_status}

	var content: String = choices[0].get("message", {}).get("content", "")
	request_completed.emit(content)
	return {
		"success": true,
		"content": content,
		"status_code": http_status,
		"usage": parsed.get("usage", {})
	}

## Generates in-character dialogue for an NPC given world context and player input.
func generate_npc_dialogue(
	character_name: String,
	personality: String,
	context_info: Dictionary,
	player_prompt: String = "",
	conversation_history: Array = []
) -> String:
	var system_prompt := _build_system_prompt(character_name, personality, context_info)

	var messages: Array = [
		{"role": "system", "content": system_prompt}
	]

	# Add past turns from history (keep last 4 to 6 for speed)
	for turn in conversation_history:
		messages.append(turn)

	# Add current player prompt or ambient event
	var user_content := player_prompt
	if user_content.strip_edges().is_empty():
		user_content = "The player approaches you while you are in the middle of your daily routine. Greet them in character."

	messages.append({"role": "user", "content": user_content})

	var result := await send_chat_request(messages)
	# Automatic fallback if model is not found or fails
	if not result.get("success", false):
		var status_code: int = int(result.get("status_code", 0))
		var err_str: String = str(result.get("error", ""))
		if status_code == 404 or "model" in err_str.to_lower():
			for fallback_model in FALLBACK_MODELS:
				if fallback_model != model:
					print("[GroqService] Model '%s' failed. Attempting fallback: %s..." % [model, fallback_model])
					var fallback_res = await send_chat_request(messages, fallback_model)
					if fallback_res.get("success", false):
						print("[GroqService] Fallback to '%s' succeeded!" % fallback_model)
						model = fallback_model
						result = fallback_res
						break

	if not result.get("success", false):
		printerr("[GroqService] Dialogue generation failed: ", result.get("error", "Unknown error"))
		return ""

	var raw_dialogue: String = result.get("content", "")
	return sanitize_dialogue(raw_dialogue, character_name)


## Generates one NPC line and contextual player prompts for a runtime choice menu.
## The JSON response format keeps model output from becoming invalid Dialogic syntax.
func generate_npc_dialogue_turn(
	character_name: String,
	personality: String,
	context_info: Dictionary,
	player_prompt: String = "",
	conversation_history: Array = []
) -> Dictionary:
	var system_prompt := _build_system_prompt(character_name, personality, context_info)
	system_prompt += """

Respond with exactly one JSON object and no markdown:
{"dialogue":"one short in-character response","choices":[{"label":"short player-facing option","prompt":"the player's full question or reply"}]}
Include two or three choices that naturally follow this exact moment. Each label must be under 45 characters and each prompt must be safe, plain player dialogue. Do not include stage directions or dialogue commands."""

	var messages: Array = [{"role": "system", "content": system_prompt}]
	for turn in conversation_history:
		messages.append(turn)

	var user_content := player_prompt
	if user_content.strip_edges().is_empty():
		user_content = "The player approaches you while you are in the middle of your daily routine. Greet them in character and offer relevant conversation options."
	messages.append({"role": "user", "content": user_content})

	var result := await send_chat_request(messages, "", {"type": "json_object"})
	if not result.get("success", false):
		var status_code: int = int(result.get("status_code", 0))
		var err_str: String = str(result.get("error", ""))
		if status_code == 404 or "model" in err_str.to_lower():
			for fallback_model in FALLBACK_MODELS:
				if fallback_model != model:
					var fallback_res := await send_chat_request(messages, fallback_model, {"type": "json_object"})
					if fallback_res.get("success", false):
						model = fallback_model
						result = fallback_res
						break

	if not result.get("success", false):
		printerr("[GroqService] Dialogue turn generation failed: ", result.get("error", "Unknown error"))
		return {}

	var parsed: Variant = JSON.parse_string(str(result.get("content", "")))
	if typeof(parsed) != TYPE_DICTIONARY:
		printerr("[GroqService] Dialogue turn was not valid JSON.")
		return {}
	var parsed_dict: Dictionary = parsed

	var dialogue := sanitize_dialogue(str(parsed_dict.get("dialogue", "")), character_name)
	if dialogue.is_empty():
		return {}

	var choices: Array = []
	var raw_choices: Variant = parsed_dict.get("choices", [])
	if raw_choices is Array:
		for raw_choice in raw_choices:
			if raw_choice is Dictionary and choices.size() < 3:
				var label := _sanitize_choice_text(str(raw_choice.get("label", "")), 45)
				var prompt := _sanitize_choice_text(str(raw_choice.get("prompt", "")), 160)
				if not label.is_empty() and not prompt.is_empty():
					choices.append({"label": label, "prompt": prompt})

	return {"dialogue": dialogue, "choices": choices}

## Cleans AI response for Dialogic 2 text box presentation.
func sanitize_dialogue(raw_text: String, character_name: String) -> String:
	var cleaned := raw_text.strip_edges()

	# 1. Remove bracketed or parenthesized stage directions: *smiles*, (chuckles)
	var regex_stage := RegEx.create_from_string(r"\*.*?\*|\(.*?\)")
	cleaned = regex_stage.sub(cleaned, "", true).strip_edges()

	# 2. Remove leading character prefixes like "John:" or "Jaiyshaan:"
	var prefix := character_name.strip_edges() + ":"
	if cleaned.to_lower().begins_with(prefix.to_lower()):
		cleaned = cleaned.substr(len(prefix)).strip_edges()

	# 3. Remove surrounding double quotes or single quotes
	while (cleaned.begins_with('"') and cleaned.ends_with('"')) or (cleaned.begins_with("'") and cleaned.ends_with("'")):
		cleaned = cleaned.substr(1, len(cleaned) - 2).strip_edges()

	# 4. Remove redundant newlines or whitespace
	cleaned = cleaned.replace("\r\n", " ").replace("\n", " ").strip_edges()
	# Dynamic text is parsed as a Dialogic timeline. Keep model output from being
	# mistaken for a Dialogic shortcode such as [signal] or [jump].
	cleaned = cleaned.replace("[", "(").replace("]", ")")

	return cleaned


func _sanitize_choice_text(value: String, max_length: int) -> String:
	var cleaned := value.replace("\r\n", " ").replace("\n", " ").strip_edges()
	cleaned = cleaned.replace("[", "(").replace("]", ")")
	if cleaned.length() > max_length:
		cleaned = cleaned.left(max_length).strip_edges()
	return cleaned

## Builds the rich system prompt grounding the NPC in Pixel Traks island.
func _build_system_prompt(character_name: String, personality: String, context_info: Dictionary) -> String:
	var time_str: String = context_info.get("time", "morning")
	var activity_str: String = context_info.get("activity", "tending the farm")
	var mood_str: String = context_info.get("mood", "friendly")

	return """You are {name}, a resident on the cozy pixel-art island called 'Pixel Traks'.
Role & Personality: {personality}
Current Island Time: {time}
Current Activity: {activity}
Current Mood: {mood}

Rules:
1. Speak in character directly to the player as {name}.
2. Keep responses brief and punchy: 1 to 2 sentences maximum (under 30 words), perfectly fitting a pixel RPG retro dialogue box.
3. React naturally to the current time of day and what you are doing on the island.
4. Never break character, never use quotes or AI disclaimers, and never write stage directions. Talk like a living game character.""".format({
		"name": character_name,
		"personality": personality,
		"time": time_str,
		"activity": activity_str,
		"mood": mood_str
	})

## Dynamically constructs a Dialogic 2 timeline resource from text and optional choices.
func create_dialogic_timeline(character_identifier: String, speech_text: String, choices: Array = []) -> DialogicTimeline:
	var timeline := DialogicTimeline.new()
	var dtl_content := "%s: %s\n" % [character_identifier, speech_text]

	for choice in choices:
		var label: String = choice.get("label", "")
		var signal_arg: String = choice.get("signal", "")
		var follow_up: String = choice.get("text", "")

		if not label.is_empty():
			dtl_content += "- %s\n" % label
			if not signal_arg.is_empty():
				dtl_content += "\t[signal arg=\"%s\"]\n" % _escape_shortcode_value(signal_arg)
			elif not follow_up.is_empty():
				dtl_content += "\t%s: %s\n" % [character_identifier, follow_up]

	timeline.from_text(dtl_content)
	return timeline


func _escape_shortcode_value(value: String) -> String:
	return value.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", " ").replace("\r", " ")
